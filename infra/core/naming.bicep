// Shared naming conventions for every project built from this template.
//
// Contract (do not change without accepting resource replacement):
//   <resource-prefix>-<location-code>-<subscription-code>-<environment>
//
// Globally unique names (Key Vault, storage accounts) spend a fixed budget and
// truncate ONLY the environment segment, so the prefix, location, subscription
// and uniqueness hash always survive.
//
// Two Bicep constraints shape these signatures:
//   1. A user-defined function cannot call subscription(), reference() or any
//      list*() function. `locationCode` and `shortHash` are therefore resolved
//      by the caller and passed in.
//   2. User-defined function parameters cannot declare defaults. Every argument
//      is passed explicitly (pass '' for an unused suffix).

@export()
@description('Resource-type abbreviations used as the leading name segment.')
var abbreviations = loadJsonContent('./abbreviations.json')

@export()
@description('Approved short codes for Azure public-cloud regions.')
var locationCodes = loadJsonContent('./location-codes.json')

@export()
@description('Per-resource-type length, charset and scope rules.')
var nameRules = loadJsonContent('./name-rules.json')

@export()
@description('Resolves an Azure region to its approved short code.')
func locationCodeFor(location string) string => string(locationCodes[toLower(location)])

@export()
@description('Normalizes an environment name for names that forbid hyphens or uppercase.')
func normalizeEnvironment(environmentName string) string => toLower(replace(environmentName, '-', ''))

@export()
@description('The shared <location>-<subscription>-<environment> body of every regional name.')
func baseName(locationCode string, subscriptionCode string, environmentName string) string =>
  '${locationCode}-${subscriptionCode}-${environmentName}'

@export()
@description('Standard regional resource name. Pass an empty suffix when the resource needs no role qualifier.')
func azName(abbreviation string, locationCode string, subscriptionCode string, environmentName string, suffix string) string =>
  empty(suffix)
    ? '${abbreviation}-${baseName(locationCode, subscriptionCode, environmentName)}'
    : '${abbreviation}-${baseName(locationCode, subscriptionCode, environmentName)}-${suffix}'

@export()
@description('Globally unique name constrained to a character budget. Only the environment segment is truncated. Use separator \'-\' for Key Vault and \'\' for storage accounts.')
func globalName(
  abbreviation string,
  locationCode string,
  subscriptionCode string,
  environmentName string,
  shortHash string,
  separator string,
  budget int
) string =>
  '${abbreviation}${separator}${locationCode}${separator}${subscriptionCode}${separator}${take(normalizeEnvironment(environmentName), max(1, budget - length('${abbreviation}${separator}${locationCode}${separator}${subscriptionCode}${separator}${separator}${shortHash}')))}${separator}${shortHash}'

@export()
@description('Short hostname-style name constrained to a character budget, such as a 15-character Windows computer name.')
func shortName(prefix string, environmentName string, shortHash string, budget int) string =>
  '${prefix}-${take(normalizeEnvironment(environmentName), max(1, budget - length('${prefix}--${shortHash}')))}-${shortHash}'
