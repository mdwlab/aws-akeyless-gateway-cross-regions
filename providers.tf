# Two aliased providers, one per region. Every resource is created by a
# child module that receives one of these via its `providers` block, so
# there is intentionally no default (unaliased) "aws" provider here.

provider "aws" {
  alias  = "east"
  region = var.east_region
}

provider "aws" {
  alias  = "west"
  region = var.west_region
}
