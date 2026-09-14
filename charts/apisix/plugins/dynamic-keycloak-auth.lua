--
-- Resolves Keycloak realm from the request Host subdomain and delegates to
-- stock openid-connect (rewrite) + authz-keycloak (access) with dynamic URLs.
--
-- Example: tenant1.expertflow.com -> realm "tenant1"
--   discovery uses public Host when use_request_host=true (matches token iss):
--   https://tenant1.expertflow.com/auth/realms/tenant1/.well-known/openid-configuration
--

local core = require("apisix.core")
local openid_connect = require("apisix.plugins.openid-connect")
local authz_keycloak = require("apisix.plugins.authz-keycloak")

local plugin_name = "dynamic-keycloak-auth"

local schema = {
    type = "object",
    properties = {
        root_domain = {type = "string", minLength = 1},
        keycloak_base_url = {type = "string", minLength = 1},
        -- When true, discovery/UMA URLs use https://{request-host}{keycloak_path}
        -- so token iss from browser login matches discovery issuer.
        use_request_host = {type = "boolean", default = true},
        keycloak_path = {type = "string", default = "/auth"},
        public_scheme = {type = "string", default = "https"},
        client_id = {type = "string", minLength = 1},
        client_secret = {type = "string", minLength = 1},
        bearer_only = {type = "boolean", default = true},
        token_signing_alg_values_expected = {type = "string", default = "RS256"},
        set_access_token_header = {type = "boolean", default = false},
        set_userinfo_header = {type = "boolean", default = false},
        timeout = {type = "integer", default = 3},
        audience = {
            type = "array",
            items = {type = "string"},
        },
        required_scopes = {
            type = "array",
            items = {type = "string"},
        },
        use_jwks = {type = "boolean", default = true},
        authz = {
            type = "object",
            properties = {
                enabled = {type = "boolean", default = true},
                lazy_load_paths = {type = "boolean", default = true},
                http_method_as_scope = {type = "boolean", default = true},
                ssl_verify = {type = "boolean", default = false},
            },
        },
    },
    required = {"root_domain", "keycloak_base_url", "client_id", "client_secret"},
}

local _M = {
    version = 0.2,
    priority = 2599,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function strip_port(host)
    if not host then
        return nil
    end
    return host:match("^([^:]+)") or host
end

local function extract_tenant(host, root_domain)
    host = strip_port(host)
    if not host or host == "" then
        return nil, "missing Host header"
    end

    host = string.lower(host)
    root_domain = string.lower(root_domain or "")

    local suffix = "." .. root_domain
    if host == root_domain then
        return nil, "apex domain is not a tenant host"
    end

    if #host <= #suffix or host:sub(-#suffix) ~= suffix then
        return nil, "host does not match root domain *." .. root_domain
    end

    local subdomain = host:sub(1, #host - #suffix)
    if subdomain == "" or subdomain:find("%.") or not subdomain:match("^[%w-]+$") then
        return nil, "invalid tenant subdomain"
    end

    return subdomain
end

local function normalize_base_url(base_url)
    return (base_url:gsub("/+$", ""))
end

local function resolve_keycloak_base(conf, ctx)
    if conf.use_request_host ~= false then
        local host = strip_port(core.request.header(ctx, "Host") or ctx.var.host)
        local scheme = conf.public_scheme or "https"
        local path = conf.keycloak_path or "/auth"
        if path ~= "" and path:sub(1, 1) ~= "/" then
            path = "/" .. path
        end
        return scheme .. "://" .. string.lower(host) .. path
    end
    return normalize_base_url(conf.keycloak_base_url)
end

local function resolve_tenant(conf, ctx)
    local host = core.request.header(ctx, "Host") or ctx.var.host
    local tenant, err = extract_tenant(host, conf.root_domain)
    if not tenant then
        return nil, err
    end
    return tenant
end

local function build_oidc_conf(conf, tenant, base)
    local oidc_conf = {
        client_id = conf.client_id,
        client_secret = conf.client_secret,
        discovery = base .. "/realms/" .. tenant .. "/.well-known/openid-configuration",
        realm = tenant,
        bearer_only = conf.bearer_only ~= false,
        -- required by openid-connect rewrite(); schema default is not applied when called programmatically
        timeout = conf.timeout or 3,
        token_signing_alg_values_expected = conf.token_signing_alg_values_expected or "RS256",
        set_access_token_header = conf.set_access_token_header == true,
        set_userinfo_header = conf.set_userinfo_header == true,
        use_jwks = conf.use_jwks ~= false,
        ssl_verify = false,
    }

    if conf.audience then
        oidc_conf.audience = conf.audience
    end
    if conf.required_scopes then
        oidc_conf.required_scopes = conf.required_scopes
    end

    return oidc_conf
end

local function build_authz_conf(conf, tenant, base)
    local authz = conf.authz or {}
    return {
        client_id = conf.client_id,
        client_secret = conf.client_secret,
        discovery = base .. "/realms/" .. tenant .. "/.well-known/uma2-configuration",
        resource_registration_endpoint = base .. "/realms/" .. tenant
            .. "/authz/protection/resource_set",
        lazy_load_paths = authz.lazy_load_paths ~= false,
        http_method_as_scope = authz.http_method_as_scope ~= false,
        ssl_verify = authz.ssl_verify == true,
        -- schema defaults are not applied when authz-keycloak is invoked programmatically
        timeout = authz.timeout or 3000,
        cache_ttl_seconds = authz.cache_ttl_seconds or (24 * 60 * 60),
        keepalive = true,
        keepalive_timeout = 60000,
        keepalive_pool = 5,
        policy_enforcement_mode = authz.policy_enforcement_mode or "ENFORCING",
        permissions = authz.permissions or {},
        grant_type = "urn:ietf:params:oauth:grant-type:uma-ticket",
        access_token_expires_in = authz.access_token_expires_in or 300,
        access_token_expires_leeway = authz.access_token_expires_leeway or 0,
        refresh_token_expires_in = authz.refresh_token_expires_in or 3600,
        refresh_token_expires_leeway = authz.refresh_token_expires_leeway or 0,
    }
end

function _M.rewrite(conf, ctx)
    local tenant, err = resolve_tenant(conf, ctx)
    if not tenant then
        core.log.warn(plugin_name, ": ", err)
        return 401, { message = "Unauthorized: " .. (err or "invalid tenant host") }
    end

    local base = resolve_keycloak_base(conf, ctx)
    ctx.dynamic_keycloak_tenant = tenant
    ctx.dynamic_keycloak_base = base
    core.log.debug(plugin_name, ": tenant=", tenant,
        " oidc_discovery=", base, "/realms/", tenant, "/.well-known/openid-configuration")

    local oidc_conf = build_oidc_conf(conf, tenant, base)
    return openid_connect.rewrite(oidc_conf, ctx)
end

function _M.access(conf, ctx)
    local authz = conf.authz or {}
    if authz.enabled == false then
        return
    end

    local tenant = ctx.dynamic_keycloak_tenant
    if not tenant then
        local err
        tenant, err = resolve_tenant(conf, ctx)
        if not tenant then
            core.log.warn(plugin_name, ": ", err)
            return 401, { message = "Unauthorized: " .. (err or "invalid tenant host") }
        end
        ctx.dynamic_keycloak_tenant = tenant
    end

    local base = ctx.dynamic_keycloak_base or resolve_keycloak_base(conf, ctx)
    -- authz-keycloak mutates conf.discovery; always pass a fresh table.
    local authz_conf = build_authz_conf(conf, tenant, base)
    return authz_keycloak.access(authz_conf, ctx)
end

return _M
