# A2A Agent Card Conformance & A2A Agent Safety rulesets (design)

Date: 2026-10-09. Status: draft, awaiting review.

## Goal

Ship two MuleSoft API Governance rulesets (AMF Validation Profile 1.0) for **A2A v1.0 Agent Cards** as
public P4A catalog entries. Organizations deploy them from P4A into their own Anypoint orgs and apply
them through governance profiles to the agent card assets they publish to Exchange.

- **A2A Agent Card Conformance** (`a2a-agent-card-conformance-ruleset`) enforces the parts of the
  card that the A2A v1.0 specification marks REQUIRED. MuleSoft's parser doesn't enforce them.
- **A2A Agent Safety** (`a2a-agent-safety-ruleset`) covers transport security, declared
  authentication, deprecated OAuth flows, and card signing.

The two are split so an org can adopt them independently. They follow the same pattern as the MCP
Server Safety and Usability rulesets in this folder.

**Relation to MuleSoft's Agent Network Best Practices** (`68ef9520-24e9-4cf2-b2f5-620025690913/agent-network-best-practices`
2.0.0). Its card rules target `agents.card` inside Agent Network specs and pin `protocolVersion` to
`0.3.x`. None of them apply to a standalone v1.0 card, so there's no overlap. The READMEs recommend
applying it alongside ours for Agent Network specs.

**Out of scope:**
- A2A v0.3 cards (`classifier: a2a-card`).
- Publishing to Exchange ourselves. P4A does that for adopters.
- Runtime enforcement, such as verifying signatures or TLS. That belongs to gateway policies.

**Source:** A2A Protocol Specification 1.0.0, https://a2a-protocol.org/latest/specification/
(snapshot 2026-10-09; proto package `lf.a2a.v1`, camelCase JSON).

## Target document

The target is the Exchange agent card asset, `agent-card.json`, with **`classifier: a2a-v1-card`**.
Only `anypoint-project-builder` 2.7.0 parses it, which ships with governance plugin **1.1.4**
(anypoint-cli-v4 1.6.27). Older plugins can't validate these assets.

## Spike results (2026-10-09, governance plugin 1.1.4; throwaway work in /tmp/a2a-spike)

**How the card is parsed**
- The bundled v1 JSON schema has `additionalProperties: false` but **no `required` lists**. A card
  missing every REQUIRED field still parses cleanly, and that gap is what the conformance ruleset fills.
- The card becomes a generic `doc:JsonLDObject` graph:
  - Every field is `core.<jsonName>`.
  - Each nested object's class is the JSON key it sits under: `core.encodes` for the card root, plus
    `core.supportedInterfaces`, `core.skills`, `core.provider`, `core.capabilities`, `core.signatures`,
    `core.oauth2SecurityScheme`, `core.apiKeySecurityScheme`, `core.flows`, `core.implicit` and so on.
- The project node is `api.Project`. It carries `catalog.classifier` and links to the card through
  `api.contract / doc.encodes`.

**Class collisions with other assets**

| Class | MCP manifest | v0.3 card |
|---|---|---|
| `core.encodes` (root) | yes | yes |
| `core.provider` | yes | yes |
| `core.capabilities` | yes | yes |
| `core.flows` | yes | yes |
| `core.skills` | no | yes |
| `core.signatures` | no | yes |
| `core.supportedInterfaces` | no | no |
| `core.oauth2SecurityScheme` | no | no |
| `core.apiKeySecurityScheme` | no | no |
| `core.openIdConnectSecurityScheme` | no | no |

`core.supportedInterfaces` and the three security-scheme wrapper classes are v1-only.

**What the validator does**
- **Card-level rules use a classifier guard.** The rule targets `api.Project`, uses
  `if: catalog.classifier in [a2a-v1-card]`, and constrains a flat path such as
  `api.contract / doc.encodes / core.skills` with `minCount: 1`.
  - It fires on v1 cards only. Verified clean on a v0.3 card and an MCP manifest.
  - It passes `validate-authoring`.
  - The finding's target is the project node with no source range, so **the message must name the
    field**.
- **`if: and: [...]` works** for conditional card-level rules. Example: the classifier guard plus
  "provider present".
- **Flat paths count values across all elements.** `core.skills / core.description minCount 1` is
  satisfied when *any* skill has a description. So per-element checks can't use the guard path.
- **Nested `propertyConstraints` under an `api.Project` path breaks validation.** Every document
  reports "Model validation is not supported for the API composite configuration".
- **Per-element rules target the element class directly**, for example `targetClass: core.skills`.
  They fire once per element with an exact source range.
  - `validate-authoring` rejects these targetClasses ("Invalid targetClass") because it has no A2A
    domain.
  - `governance:ruleset:validate` accepts them. That is the validator P4A's worker runs
    (`worker/ruleset-pipeline.ts`).
- **`in: [true]` ignores a missing value.** Pair it with `minCount: 1`.

## Rule catalog

Severity tiers:
- `violation`: breaks the spec or is unsafe.
- `warning`: the spec says SHOULD, or it's a strong recommendation.
- `info`: nice to have.

"G" in the tables means the classifier guard: `targetClass: api.Project`,
`if: catalog.classifier in [a2a-v1-card]`, with paths rooted at `api.contract / doc.encodes`.
Both profiles declare these prefixes:

```yaml
prefixes:
  api: http://anypoint.com/vocabs/api#
  catalog: http://anypoint.com/vocabs/digital-repository#
```

### A2A Agent Card Conformance (Exchange asset `a2a-agent-card-conformance`, 1.0.0)

Required string fields use `minCount: 1` with `minLength: 1`. An empty `protocolVersion` means 0.3
under the spec, so it must not pass. Required arrays use `minCount: 1`, because the spec says
required arrays MUST contain at least one element.

| Rule ID | Target | Constraint | Severity |
|---|---|---|---|
| `card-name-required` | G | `core.name` present, non-empty | violation |
| `card-description-required` | G | `core.description` present, non-empty | violation |
| `card-version-required` | G | `core.version` present, non-empty | violation |
| `card-capabilities-required` | G | `core.capabilities` minCount 1 | violation |
| `card-supported-interfaces-required` | G | `core.supportedInterfaces` minCount 1 | violation |
| `card-default-input-modes-required` | G | `core.defaultInputModes` minCount 1 | violation |
| `card-default-output-modes-required` | G | `core.defaultOutputModes` minCount 1 | violation |
| `card-skills-required` | G | `core.skills` minCount 1 | violation |
| `provider-complete` | G + `if and` (provider present) | `core.provider / core.organization` and `core.provider / core.url` present, non-empty | violation |
| `interface-url-required` | `core.supportedInterfaces` | `core.url` present, non-empty | violation |
| `interface-protocol-binding-required` | `core.supportedInterfaces` | `core.protocolBinding` present, non-empty | violation |
| `interface-protocol-version-required` | `core.supportedInterfaces` | `core.protocolVersion` present, non-empty | violation |
| `interface-protocol-version-format` | `core.supportedInterfaces` | `core.protocolVersion` pattern `^[0-9]+\.[0-9]+$` (the spec says patch versions SHOULD NOT be used) | warning |
| `interface-protocol-binding-known` | `core.supportedInterfaces` | `core.protocolBinding` in `[JSONRPC, GRPC, HTTP+JSON]` (custom bindings are allowed, so this is a warning) | warning |
| `skill-id-required` | `core.skills` | `core.id` present, non-empty | violation |
| `skill-name-required` | `core.skills` | `core.name` present, non-empty | violation |
| `skill-description-required` | `core.skills` | `core.description` present, non-empty | violation |
| `skill-tags-required` | `core.skills` | `core.tags` minCount 1 | violation |
| `signature-complete` | `core.signatures` | `core.protected` and `core.signature` present, non-empty | violation |

The `skill-*` and `signature-complete` rules also run on v0.3 cards. v0.3 has the same requirements
for these objects, so a compliant v0.3 card produces no findings. The cross-check below pins this.

### A2A Agent Safety (Exchange asset `a2a-agent-safety`, 1.0.0)

| Rule ID | Target | Constraint | Severity |
|---|---|---|---|
| `interface-url-https` | `core.supportedInterfaces` | `core.url` pattern `^https://` (the spec says production MUST use encrypted transport) | violation |
| `extended-card-requires-auth` | G + `if and` (`core.capabilities / core.extendedAgentCard` minCount 1 + in `[true]`) | `core.securitySchemes` and `core.securityRequirements` minCount 1 (the spec says the extended card MUST be authenticated with a scheme declared in the public card) | violation |
| `oauth-no-implicit-flow` | `core.oauth2SecurityScheme` | `core.flows / core.implicit` maxCount 0 (deprecated) | violation |
| `oauth-no-password-flow` | `core.oauth2SecurityScheme` | `core.flows / core.password` maxCount 0 (deprecated) | violation |
| `oauth-metadata-url-https` | `core.oauth2SecurityScheme` | `core.oauth2MetadataUrl` pattern `^https://` (the spec says "TLS is required") | violation |
| `oidc-url-https` | `core.openIdConnectSecurityScheme` | `core.openIdConnectUrl` pattern `^https://` | violation |
| `card-security-declared` | G | `core.securitySchemes` and `core.securityRequirements` minCount 1 | warning |
| `oauth-pkce-required` | `core.oauth2SecurityScheme`, if `core.flows / core.authorizationCode` minCount 1 | `core.flows / core.authorizationCode / core.pkceRequired` minCount 1 + in `[true]` | warning |
| `api-key-not-in-query` | `core.apiKeySecurityScheme` | `core.location` in `[header, cookie]` (query strings leak into logs) | warning |
| `card-signed` | G | `core.signatures` minCount 1 | info |

A card that sets `extendedAgentCard: true` and declares no security also fails `card-security-declared`.
That bad fixture carries an `expected` file listing both findings.

`oidc-url-https` and `oauth-metadata-url-https` use class and field names inferred from the v1 schema,
not probed yet. Their bad fixtures confirm them during implementation.

### Every rule carries

- `message`: one line that names the field, the problem and the fix. The field name matters most on
  G rules, whose findings have no source range. Example: "Agent Card has no `skills`. Declare at least
  one AgentSkill (A2A v1.0: AgentCard.skills is REQUIRED)."
- `documentation`: why it matters, and the spec section it comes from.
- `examples.valid` and `examples.invalid`: minimal agent cards.

## Repository layout (each repo)

```
ruleset.yaml               # the profile; P4A auto-discovers it at the repo root
exchange.json              # assetId, name, description, main: ruleset.yaml, version
fixtures/good/             # fully compliant v1.0 card that passes BOTH rulesets; 0 findings
fixtures/bad/<rule-id>[.<variant>]/   # violates one rule; an optional `expected` file lists every finding when rules overlap
fixtures/scope/v03-card/   # compliant v0.3 card (classifier a2a-card); must produce 0 findings
fixtures/scope/mcp-manifest/   # MCP manifest (classifier mcp-metadata); must produce 0 findings
scripts/check.sh           # the test suite (below)
README.md                  # purpose, pairing note, rule table (id/severity/why/fix), limitations, CLI requirement, deploy via P4A, Source Ref + date
CHANGELOG.md
.envrc                     # GH_TOKEN for tbolis-at-mulesoft
```

Each v1 fixture folder holds `agent-card.json` plus an `exchange.json` with
`"classifier": "a2a-v1-card"`, `"descriptorVersion": "1.0.0"` and `"main": "agent-card.json"`.

The design spec and implementation plan live in the conformance repo under `docs/superpowers/`.
Until the repos exist, the spec lives in the container folder at
`ms-omni-governance-rulesets/docs/superpowers/specs/`.

## Testing (`scripts/check.sh`)

Adapted from the MCP repos' script.

1. **CLI.** Use `${ANYPOINT_CLI:-anypoint-cli-v4}`. Print the CLI and governance plugin versions, and
   fail if the plugin is older than 1.1.4.
2. **Tier-1 lint.**
   - Profile header and non-empty name.
   - The `api` and `catalog` prefixes are declared.
   - Severity lists and `validations:` keys match, with no duplicates.
   - Size is under 512 KB.
3. **`validate-authoring`.** The only errors allowed are `Invalid targetClass` for an allowlisted
   class: `core.supportedInterfaces`, `core.skills`, `core.signatures`, `core.oauth2SecurityScheme`,
   `core.apiKeySecurityScheme` and `core.openIdConnectSecurityScheme`. Any other error or warning
   fails.
4. **`governance:ruleset:validate`** reports that the ruleset conforms with the dialect.
5. **`fixtures/good`** reports 0 findings, no `example-validation-error`, and no legacy-mode fallback.
6. **`fixtures/scope/*`** each report 0 findings. This is the regression test for the class
   collisions.
7. **Each `fixtures/bad/<id>[.<variant>]`** produces exactly `{<id>:<Severity>}`, or exactly the
   findings in its `expected` file.
8. **Coverage.** Every rule has at least one bad fixture, and every bad fixture maps to a rule.

**Cross-check:** each ruleset runs clean against the sibling repo's `fixtures/good`.

Bad fixtures to include beyond the one-per-rule minimum:
- a second skill or interface missing the field, proving per-element checks;
- an empty-string variant of each required string;
- an empty-array variant for each required array;
- `provider-complete` missing the organization, and separately missing the url.

## Limitations (documented in the READMEs)

- **Hosted support is unverified.** Validating `a2a-v1-card` needs project-builder 2.7.0 (governance
  plugin 1.1.4+). It isn't yet proven that Anypoint's hosted governance (console profiles, Exchange
  conformance) validates these assets. The dogfood step must prove it before any P4A submission is
  marked ready.
- **Card-level findings have no source location**, because of the classifier guard. Messages name the
  field instead.
- **`securityRequirements` can't be cross-checked against `securitySchemes` names.** Scheme names are
  map keys, which the validation profile can't iterate or join on.
- **Signatures are checked for presence and shape only.** JWS verification and JCS canonicalization
  are runtime concerns.
- **`interface-url-https`** also flags local development cards. That is intended for governed Exchange
  assets.
- **`validate-authoring` false errors.** It doesn't model A2A v1, so it reports the allowlisted
  per-element targetClasses as errors. `governance:ruleset:validate` and the per-rule fixtures are the
  real gates.

## Delivery

1. Create the two public repos `P4A-Policies-for-Agents/a2a-agent-card-conformance-ruleset` and
   `P4A-Policies-for-Agents/a2a-agent-safety-ruleset`. This needs explicit approval.
2. Clone both into this container, add `.envrc`, and add
   them to the container `CLAUDE.md` along with an "A2A v1 gotchas" section.
3. Write the implementation plan (`superpowers:writing-plans`), then implement test-first, one rule
   at a time. Conformance comes first.
4. Run `check.sh` and the cross-checks, then report the results.
5. **⏸ Hold.** P4A submission waits for explicit approval. When approved:
   - `targetScopes: ["agent-network"]`
   - tags `a2a`, `agent`, plus `conformance` or `security`
   - `examplesUrl` pointing to `fixtures/`
   - `sourceRef` `v1.0.0`
6. After approval and review, dogfood with `deploy_ruleset` into our own test org (approved
   separately) plus a draft console profile on a published v1 card asset. This settles the
   hosted-support question.
