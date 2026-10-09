# A2A Agent Card Conformance ruleset

A MuleSoft API Governance ruleset (AMF Validation Profile 1.0) for **A2A v1.0 Agent Cards**:
Exchange assets with classifier `a2a-v1-card`. It enforces the fields the A2A v1.0 specification
marks REQUIRED. Anypoint's agent card schema accepts cards that leave them out.

**Pairs with:**
- [A2A Agent Safety](https://github.com/P4A-Policies-for-Agents/a2a-agent-safety-ruleset), for
  transport security, authentication and signing.
- MuleSoft's *Agent Network Best Practices*, for Agent Network specs. Its card rules target
  v0.3 cards inside Agent Network specs, so they don't overlap with this ruleset.

## Rules

| Rule | Severity | Why | Fix |
|---|---|---|---|
| `card-name-required` | violation | AgentCard.name is REQUIRED | Set a non-empty `name` |
| `card-description-required` | violation | AgentCard.description is REQUIRED | Set a non-empty `description` |
| `card-version-required` | violation | AgentCard.version is REQUIRED | Set a non-empty `version` |
| `card-capabilities-required` | violation | AgentCard.capabilities is REQUIRED | Add `capabilities` |
| `card-supported-interfaces-required` | violation | Without interfaces the agent is unreachable | Add at least one `supportedInterfaces` entry |
| `card-default-input-modes-required` | violation | AgentCard.defaultInputModes is REQUIRED | List at least one media type |
| `card-default-output-modes-required` | violation | AgentCard.defaultOutputModes is REQUIRED | List at least one media type |
| `card-skills-required` | violation | AgentCard.skills is REQUIRED | Declare at least one skill |
| `provider-complete` | violation | AgentProvider.organization and .url are REQUIRED | Set both, or remove `provider` |
| `interface-url-required` | violation | AgentInterface.url is REQUIRED | Set the interface URL |
| `interface-protocol-binding-required` | violation | AgentInterface.protocolBinding is REQUIRED | Set the binding |
| `interface-protocol-version-required` | violation | Empty means 0.3 | Set e.g. `1.0` |
| `interface-protocol-version-format` | warning | Patch versions SHOULD NOT be used | Use Major.Minor |
| `interface-protocol-binding-known` | warning | Generic clients speak only core bindings | Use JSONRPC, GRPC or HTTP+JSON |
| `skill-id-required` | violation | AgentSkill.id is REQUIRED | Set `id` |
| `skill-name-required` | violation | AgentSkill.name is REQUIRED | Set `name` |
| `skill-description-required` | violation | AgentSkill.description is REQUIRED | Set `description` |
| `skill-tags-required` | violation | AgentSkill.tags is REQUIRED | Add at least one tag |
| `signature-complete` | violation | `protected` and `signature` are REQUIRED | Set both on every signature |
| `card-json-camel-case` | violation | JSON MUST be camelCase; aliases hide fields | Rename snake_case card fields |
| `interface-json-camel-case` | violation | Same, for interfaces | Rename `protocol_binding`/`protocol_version` |
| `skill-json-camel-case` | violation | Same, for skills | Rename `input_modes`/`output_modes`/`security_requirements` |

The `skill-*` and `signature-complete` rules also run on v0.3 cards, which have the same
requirements. A compliant v0.3 card produces no findings.

## Deploy it to your org

Find this ruleset in the [P4A catalog](https://www.p4a.ai) and deploy it to your Anypoint org,
either with **Publish to Exchange** or with the P4A MCP server's `deploy_ruleset`. Then apply it
through a governance profile that covers your A2A agent card assets.

## Limitations

- **Hosted support is unverified.** Validating `a2a-v1-card` assets needs governance plugin
  1.1.4 or later. It isn't yet confirmed that Anypoint's hosted governance validates these
  assets.
- **Card-level findings have no source location.** The `card-*` and `provider-complete` rules
  are reported on the asset, so their messages name the field.
- **`validate-authoring` false errors.** It has no A2A domain, so it reports `Invalid
  targetClass` for `core.supportedInterfaces`, `core.skills` and `core.signatures`.
  `governance:ruleset:validate` accepts the ruleset, and the fixtures prove each rule.
- **v0.3 cards are out of scope.** Only `skill-*` and `signature-complete` reach them.
- **snake_case aliases are matched through `snake*` prefixes.** Compact IRIs can't contain
  `_`, so a path such as `core.icon_url` makes the validator panic. `ruleset.yaml` declares
  prefixes whose namespace ends with the alias's leading words (`snakeIcon:
  http://a.ml/vocabularies/core#icon_`), and the rules use paths like `snakeIcon.url`. Each alias
  has its own bad fixture.

## Development

`scripts/check.sh` needs governance plugin **1.1.4 or later**. One way to install it without
touching your global CLI:

```bash
mkdir -p ~/.cache/p4a-a2a-cli && cd ~/.cache/p4a-a2a-cli
echo '{"private":true,"dependencies":{"anypoint-cli-v4-public":"1.6.27"},"overrides":{"mulesoft-anypoint-cli-governance-plugin":"1.1.4"}}' > package.json
npm install --no-audit --no-fund
```

Then, from the repo root:

```bash
python3 -I scripts/fixtures.py
ANYPOINT_CLI=~/.cache/p4a-a2a-cli/node_modules/.bin/anypoint-cli-v4 scripts/check.sh
```

- `scripts/fixtures.py` generates every fixture: a compliant card, scope documents that must
  stay clean (a v0.3 card, an MCP manifest, a v1 card without `provider`), and one bad card per
  rule. Never edit `fixtures/` by hand.
- Bump `version` in `exchange.json` for every rule change.

## Source Ref

A2A Protocol Specification 1.0.0, https://a2a-protocol.org/latest/specification/ (snapshot
2026-10-09).
