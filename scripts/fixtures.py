"""Generate fixtures/ from GOOD plus one mutation per bad fixture.

Run from the repo root:  python3 -I scripts/fixtures.py
This deletes and rewrites fixtures/. Never edit fixtures/ by hand.

Bad fixture names are <rule-id> or <rule-id>.<variant>. scripts/check.sh expects
each one to produce exactly one finding, for <rule-id>, unless EXPECTED lists the
full set of findings (written to the fixture's `expected` file).
"""
import copy
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent / "fixtures"

# --- Keep everything from here to "per-repo" identical in both A2A ruleset repos. ---

# A2A v1.0 card that passes BOTH A2A Agent Card Conformance and A2A Agent Safety.
GOOD = {
    "name": "Weather Agent",
    "description": "Answers questions about current weather and forecasts for a city.",
    "supportedInterfaces": [
        {"url": "https://weather.example.com/a2a/v1", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"},
        {"url": "https://weather.example.com/a2a/grpc", "protocolBinding": "GRPC", "protocolVersion": "1.0"},
    ],
    "provider": {"organization": "Example Corp", "url": "https://example.com"},
    "version": "1.0.0",
    "documentationUrl": "https://example.com/docs/weather-agent",
    "capabilities": {"streaming": True, "pushNotifications": False, "extendedAgentCard": True},
    "securitySchemes": {
        "bearer": {"httpAuthSecurityScheme": {"scheme": "Bearer", "bearerFormat": "JWT"}},
        "oauth": {
            "oauth2SecurityScheme": {
                "oauth2MetadataUrl": "https://auth.example.com/.well-known/oauth-authorization-server",
                "flows": {
                    "authorizationCode": {
                        "authorizationUrl": "https://auth.example.com/authorize",
                        "tokenUrl": "https://auth.example.com/token",
                        "scopes": {"weather:read": "Read weather data"},
                        "pkceRequired": True,
                    }
                },
            }
        },
        "oidc": {
            "openIdConnectSecurityScheme": {
                "openIdConnectUrl": "https://id.example.com/.well-known/openid-configuration"
            }
        },
        "key": {"apiKeySecurityScheme": {"location": "header", "name": "X-API-Key"}},
    },
    "securityRequirements": [
        {"schemes": {"bearer": {"list": []}}},
        {"schemes": {"oauth": {"list": ["weather:read"]}}},
    ],
    "defaultInputModes": ["text/plain"],
    "defaultOutputModes": ["text/plain", "application/json"],
    "skills": [
        {
            "id": "current-weather",
            "name": "Current weather",
            "description": "Reports the current weather for a city.",
            "tags": ["weather"],
            "examples": ["What's the weather in Paris?"],
        },
        {
            "id": "forecast",
            "name": "Forecast",
            "description": "Gives a five-day forecast for a city.",
            "tags": ["weather", "forecast"],
        },
    ],
    "signatures": [{"protected": "eyJhbGciOiJFUzI1NiJ9", "signature": "c2lnbmF0dXJl"}],
}

# v0.3 card (classifier a2a-card). Its required fields are complete, but its transport and auth
# are insecure, so a v1 rule leaking onto a colliding v0.3 class shows up as a finding.
V03_CARD = {
    "protocolVersion": "0.3.0",
    "name": "Weather Agent",
    "description": "Answers questions about current weather and forecasts for a city.",
    "url": "http://weather.example.com/a2a",
    "preferredTransport": "JSONRPC",
    "provider": {"organization": "Example Corp", "url": "https://example.com"},
    "version": "1.0.0",
    "capabilities": {"streaming": True, "pushNotifications": False},
    "securitySchemes": {
        "legacy": {
            "type": "oauth2",
            "flows": {"implicit": {"authorizationUrl": "http://auth.example.com/authorize", "scopes": {}}},
        },
        "key": {"type": "apiKey", "in": "query", "name": "api_key"},
    },
    "security": [{"legacy": []}],
    "defaultInputModes": ["text/plain"],
    "defaultOutputModes": ["text/plain"],
    "skills": [
        {"id": "current-weather", "name": "Current weather", "description": "Reports the current weather.", "tags": ["weather"]}
    ],
}

# MCP manifest (classifier mcp-metadata) that reuses the colliding classes core.encodes,
# core.provider, core.capabilities and core.flows, with insecure values.
MCP_MANIFEST = {
    "protocolVersion": "2025-06-18",
    "transport": {"kind": "streamableHttp", "path": "/mcp"},
    "provider": {"organization": "Example Corp", "url": "http://example.com"},
    "capabilities": {"tools": {}},
    "securitySchemes": {
        "legacy": {
            "type": "oauth2",
            "flows": {
                "implicit": {"authorizationUrl": "http://auth.example.com/authorize", "scopes": {}},
                "password": {"tokenUrl": "http://auth.example.com/token", "scopes": {}},
            },
        },
        "key": {"type": "apiKey", "in": "query", "name": "api_key"},
        "oidc": {"type": "openIdConnect", "openIdConnectUrl": "http://id.example.com/.well-known/openid-configuration"},
    },
    "tools": [
        {"name": "get_weather", "description": "Gets the current weather for a city.", "inputSchema": {"type": "object", "properties": {}}}
    ],
}

# Documents both rulesets must accept with 0 findings: name -> (main file, classifier, document).
SCOPE = {
    "v03-card": ("agent-card.json", "a2a-card", V03_CARD),
    "mcp-manifest": ("mcp-metadata.json", "mcp-metadata", MCP_MANIFEST),
    # provider is optional in v1.0; provider-complete must not fire when it is absent.
    "v1-no-provider": ("agent-card.json", "a2a-v1-card", {k: v for k, v in GOOD.items() if k != "provider"}),
}


def iface(d, i=0):
    return d["supportedInterfaces"][i]


def skill(d, i=0):
    return d["skills"][i]


def scheme(d, name):
    """The wrapped scheme object, e.g. scheme(d, "oauth") -> the oauth2SecurityScheme dict."""
    return next(iter(d["securitySchemes"][name].values()))


def oauth_flows(d):
    return scheme(d, "oauth")["flows"]


def put(obj, key, value):
    obj[key] = value


def rename(obj, old, new):
    obj[new] = obj.pop(old)


def write(name, doc, main_file="agent-card.json", classifier="a2a-v1-card", expected=None):
    path = ROOT / name
    path.mkdir(parents=True)
    (path / main_file).write_text(json.dumps(doc, indent=2) + "\n")
    asset = name.replace("/", "-").replace(".", "-")
    exchange = {
        "main": main_file,
        "name": asset,
        "groupId": "p4a-fixtures",
        "assetId": asset,
        "version": "1.0.0",
        "classifier": classifier,
        "descriptorVersion": "1.0.0",
    }
    (path / "exchange.json").write_text(json.dumps(exchange, indent=2) + "\n")
    if expected:
        (path / "expected").write_text("".join(f"{line}\n" for line in sorted(expected)))


# --- per-repo: bad fixtures for this ruleset ---

BAD = {
    "card-name-required": lambda d: d.pop("name"),
    "card-name-required.empty": lambda d: put(d, "name", ""),
    "card-description-required": lambda d: d.pop("description"),
    "card-description-required.empty": lambda d: put(d, "description", ""),
    "card-version-required": lambda d: d.pop("version"),
    "card-version-required.empty": lambda d: put(d, "version", ""),
    "card-capabilities-required": lambda d: d.pop("capabilities"),
    "card-supported-interfaces-required": lambda d: d.pop("supportedInterfaces"),
    "card-supported-interfaces-required.empty-array": lambda d: put(d, "supportedInterfaces", []),
    "card-default-input-modes-required": lambda d: d.pop("defaultInputModes"),
    "card-default-input-modes-required.empty-array": lambda d: put(d, "defaultInputModes", []),
    "card-default-output-modes-required": lambda d: d.pop("defaultOutputModes"),
    "card-default-output-modes-required.empty-array": lambda d: put(d, "defaultOutputModes", []),
    "card-skills-required": lambda d: d.pop("skills"),
    "card-skills-required.empty-array": lambda d: put(d, "skills", []),
    "provider-complete.no-organization": lambda d: d["provider"].pop("organization"),
    "provider-complete.no-url": lambda d: d["provider"].pop("url"),
    "provider-complete.empty-url": lambda d: put(d["provider"], "url", ""),
    "interface-url-required": lambda d: iface(d).pop("url"),
    # Review Focus 3: only the second interface is broken.
    "interface-url-required.second-interface": lambda d: iface(d, 1).pop("url"),
    "interface-url-required.empty": lambda d: put(iface(d), "url", ""),
    "interface-protocol-binding-required": lambda d: iface(d).pop("protocolBinding"),
    "interface-protocol-binding-required.empty": lambda d: put(iface(d), "protocolBinding", ""),
    "interface-protocol-version-required": lambda d: iface(d).pop("protocolVersion"),
    "interface-protocol-version-required.empty": lambda d: put(iface(d), "protocolVersion", ""),
    "interface-protocol-version-format": lambda d: put(iface(d), "protocolVersion", "1.0.0"),
    "interface-protocol-version-format.second-interface": lambda d: put(iface(d, 1), "protocolVersion", "v1"),
    "interface-protocol-binding-known": lambda d: put(iface(d), "protocolBinding", "SOAP"),
    "skill-id-required": lambda d: skill(d).pop("id"),
    # Review Focus 3: only the second skill is broken.
    "skill-id-required.second-skill": lambda d: skill(d, 1).pop("id"),
    "skill-name-required": lambda d: skill(d).pop("name"),
    "skill-name-required.empty": lambda d: put(skill(d), "name", ""),
    "skill-description-required": lambda d: skill(d).pop("description"),
    "skill-description-required.second-skill": lambda d: skill(d, 1).pop("description"),
    "skill-description-required.empty": lambda d: put(skill(d), "description", ""),
    "skill-tags-required": lambda d: skill(d).pop("tags"),
    "skill-tags-required.empty-array": lambda d: put(skill(d), "tags", []),
    "signature-complete.no-protected": lambda d: d["signatures"][0].pop("protected"),
    "signature-complete.no-signature": lambda d: d["signatures"][0].pop("signature"),
    "signature-complete.empty-signature": lambda d: put(d["signatures"][0], "signature", ""),
    "card-json-camel-case": lambda d: put(d, "icon_url", "https://example.com/icon.png"),
    "card-json-camel-case.supported-interfaces": lambda d: rename(d, "supportedInterfaces", "supported_interfaces"),
    "interface-json-camel-case": lambda d: rename(iface(d), "protocolVersion", "protocol_version"),
    "skill-json-camel-case": lambda d: put(skill(d), "input_modes", ["text/plain"]),
    # One fixture per alias, so a typo in a snake* prefix namespace (ruleset.yaml) can't hide.
    "card-json-camel-case.default-input-modes": lambda d: put(d, "default_input_modes", ["text/plain"]),
    "card-json-camel-case.default-output-modes": lambda d: put(d, "default_output_modes", ["text/plain"]),
    "card-json-camel-case.documentation-url": lambda d: put(d, "documentation_url", "https://example.com/docs"),
    "card-json-camel-case.security-schemes": lambda d: put(d, "security_schemes", copy.deepcopy(d["securitySchemes"])),
    "card-json-camel-case.security-requirements": lambda d: put(d, "security_requirements", copy.deepcopy(d["securityRequirements"])),
    "interface-json-camel-case.protocol-binding": lambda d: put(iface(d), "protocol_binding", "JSONRPC"),
    "skill-json-camel-case.output-modes": lambda d: put(skill(d), "output_modes", ["text/plain"]),
    "skill-json-camel-case.security-requirements": lambda d: put(skill(d), "security_requirements", copy.deepcopy(d["securityRequirements"])),
}

# Fixtures that legitimately trip more than one rule: name -> every "<id>:<Severity>" expected.
EXPECTED = {
    "interface-protocol-binding-required.empty": [
        "interface-protocol-binding-required:Violation",
        "interface-protocol-binding-known:Warning",
    ],
    "interface-protocol-version-required.empty": [
        "interface-protocol-version-required:Violation",
        "interface-protocol-version-format:Warning",
    ],
    "card-json-camel-case.supported-interfaces": [
        "card-json-camel-case:Violation",
        "card-supported-interfaces-required:Violation",
    ],
    "interface-json-camel-case": [
        "interface-json-camel-case:Violation",
        "interface-protocol-version-required:Violation",
    ],
}


def main():
    unknown = set(EXPECTED) - set(BAD)
    if unknown:
        raise SystemExit(f"EXPECTED names without a BAD entry: {sorted(unknown)}")
    shutil.rmtree(ROOT, ignore_errors=True)
    write("good", GOOD)
    for name, (main_file, classifier, doc) in SCOPE.items():
        write(f"scope/{name}", doc, main_file, classifier)
    for name, mutate in BAD.items():
        doc = copy.deepcopy(GOOD)
        mutate(doc)
        write(f"bad/{name}", doc, expected=EXPECTED.get(name))


if __name__ == "__main__":
    main()
