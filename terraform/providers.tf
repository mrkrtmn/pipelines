provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "botwb"
      ManagedBy = "terraform"
    }
  }
}
