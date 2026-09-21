// Common tag set applied to every resource in every project built from this
// template. Keeping this in one place is what stopped consuming repositories
// from inventing their own tag schemes.
//
// Base tags are always emitted. `owner` and `cost-center` are emitted only when
// a non-empty value is supplied, so an unset value never produces an empty tag.

@export()
@description('Builds the common tag object. Pass empty strings for owner and costCenter to omit those tags entirely.')
func commonTags(
  repository string,
  environmentName string,
  deploymentProfile string,
  createdOn string,
  lastUpdatedOn string,
  owner string,
  costCenter string
) object =>
  union(
    {
      repository: repository
      'azd-env-name': environmentName
      environment: environmentName
      profile: deploymentProfile
      'managed-by': 'azd'
      'created-on': createdOn
      'last-updated-on': lastUpdatedOn
    },
    empty(owner)
      ? {}
      : {
          owner: owner
        },
    empty(costCenter)
      ? {}
      : {
          'cost-center': costCenter
        }
  )
