# viget.context

Forked / copied from [cloudposse/terraform-null-label](https://github.com/cloudposse/terraform-null-label)

This project includes source code that is licensed under the Apache License 2.0 (see LICENSE file) and additional code which is licensed under the Apache License 2.0 (see LICENSE-TF-CONTEXT file).

Terraform module designed to generate consistent names and tags for resources. Use `terraform-context` to implement a strict naming convention.

There are 6 inputs considered "labels" or "ID elements" (because the labels are used to construct the ID):
1. namespace
2. tenant
4. component
5. attributes

This module generates IDs using the following convention by default: `{namespace}-{stage}-{component}-{attributes}`.
However, it is highly configurable. The delimiter (e.g. `-`) is configurable. Each label item is optional (although you must provide at least one).
and the label `id` will look like `{namespace}-{stage}-{component}-{attributes}`.
- The `tenant` label was introduced in v0.25.0. To preserve backward compatibility, it is not included by default.
- The `attributes` input is actually a list of strings and `{attributes}` expands to the list elements joined by the delimiter.
- If `attributes` is excluded but `namespace`, `stage`, and `component` are included, `id` will look like `{namespace}-{stage}-{component}`.
  Excluding `attributes` is discouraged, though, because attributes are the main way modules modify the ID to ensure uniqueness when provisioning the same resource types.
- If you want the label items in a different order, you can specify that, too, with the `label_order` list.
- You can set a maximum length for the `id`, and the module will create a (probably) unique name that fits within that length.
  (The module uses a portion of the MD5 hash of the full `id` to represent the missing part, so there remains a slight chance of name collision.)
- You can control the letter case of the generated labels which make up the `id` using `var.label_value_case`.
- By default, all of the non-empty labels are also exported as tags, whether they appear in the `id` or not.
You can control which labels are exported as tags by setting `labels_as_tags` to the list of labels you want exported,
or the empty list `[]` if you want no labels exported as tags at all. Tags passed in via the `tags` variable are
always exported, and regardless of settings, empty labels are never exported as tags.
You can control the case of the tag names (keys) for the labels using `var.label_key_case`.
Unlike the tags generated from the label inputs, tags passed in via the `tags` input are not modified.

It's recommended to use one `terraform-context` module for every unique resource of a given resource type.
For example, if you have 10 instances, there should be 10 different labels.
However, if you have multiple different kinds of resources (e.g. instances, security groups, file systems, and elastic ips), then they can all share the same label assuming they are logically related.

For most purposes, the `id` output is sufficient to create an ID or label for a resource, and if you want a different
ID or a different format, you would instantiate another instance of `context` and configure it accordingly. However,
to accomodate situations where you want all the same inputs to generate multiple descriptors, this module provides
the `descriptors` output, which is a map of strings generated according to the format specified by the
`descriptor_formats` input. This feature is intentionally simple and minimally configurable and will not be
enhanced to add more features that are already in `context`.

All [Viget Terraform modules](https://github.com/vigetlabs?q=terraform-) should use this module to ensure resources can be instantiated multiple times within an account and without conflict.

The Viget convention is to use labels as follows:
- `namespace`: A short (3-4 letters) abbreviation of the company name, to ensure globally unique IDs for things like S3 buckets
- `tenant`: _(Rarely needed)_ When a company creates a dedicated resource per customer, `tenant` can be used to identify the customer the resource is dedicated to
- `stage`: The role of the resource such as `prod`, `staging`, `source`, `build`, `test`, `deploy`, `release`
- `component`: The name of the component or solution that owns the resources, such as `eks`, `rds`, or `app`


## Usage


**IMPORTANT:** We do not pin modules to versions in our examples because of the
difficulty of keeping the versions in the documentation in sync with the latest released versions.
We highly recommend that in your code you pin the version to the exact version you are
using so that your infrastructure remains stable, and update versions in a
systematic way so that they do not catch you by surprise.


### Defaults

Viget Terraform modules share a common `context` object that is meant to be passed from module to module.
The context object is a single object that contains all the input values for `terraform-context`.
However, each input value can also be specified individually by name as a standard Terraform variable,
and the value of those variables, when set to something other than `null`, will override the value
in the context object. In order to allow chaining of these objects, where the context object input to one
module is transformed and passed on to the next module, all the variables default to `null` or empty collections.
The actual default values used when nothing is explicitly set are described in the documentation below.

For example, the default value of `delimiter` is shown as `null`, but if you leave it set to `null`,
`terraform-context` will actually use the default delimiter `-` (hyphen).

A non-obvious but intentional consequence of this design is that once a module sets a non-default value,
future modules in the chain cannot reset the value back to the original default. Instead, the new setting
becomes the new default for downstream modules. Also, collections are not overwritten, they are merged,
so once a tag is added, it will remain in the tag set and cannot be removed, although its value can
be overwritten.

Because the purpose of `labels_as_tags` is primarily to prevent tags from being generated
that would [conflict with the AWS provider's `default_tags`](https://github.com/hashicorp/terraform-provider-aws/issues/19204), it is an exception to the
rule that variables override the setting in the context object. The value in the context
object cannot be changed, so that later modules cannot re-enable a problematic tag.

### Simple Example

```hcl
module "eg_prod_bastion_label" {
  source   = "github.com/vigetlabs/terraform-context.git"
  # We recommend pinning every module to a specific version
  # source = "github.com/vigetlabs/terraform-context.git?ref=vx.x.x"

  namespace  = "eg"
  stage      = "prod"
  name       = "bastion"
  attributes = ["public"]
  delimiter  = "-"

  tags = {
    "BusinessUnit" = "XYZ",
    "Snapshot"     = "true"
  }
}
```

This will create an `id` with the value of `eg-prod-bastion-public` because when generating `id`, the default order is `namespace`, `environment`, `stage`,  `name`, `attributes`
(you can override it by using the `label_order` variable, see [Advanced Example 3](#advanced-example-3)).

Now reference the label when creating an instance:

```hcl
resource "aws_instance" "eg_prod_bastion_public" {
  instance_type = "t1.micro"
  tags          = module.eg_prod_bastion_label.tags
}
```

Or define a security group:

```hcl
resource "aws_security_group" "eg_prod_bastion_public" {
  vpc_id = var.vpc_id
  name   = module.eg_prod_bastion_label.id
  tags   = module.eg_prod_bastion_label.tags
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```


### Advanced Example

Here is a more complex example with two instances using two different labels. Note how efficiently the tags are defined for both the instance and the security group.

<details><summary>Click to show</summary>

```hcl
module "eg_prod_bastion_label" {
  source   = "github.com/vigetlabs/terraform-context.git"
  # We recommend pinning every module to a specific version
  # source = "github.com/vigetlabs/terraform-context.git?ref=vx.x.x"

  namespace  = "eg"
  stage      = "prod"
  name       = "bastion"
  delimiter  = "-"

  tags = {
    "BusinessUnit" = "XYZ",
    "Snapshot"     = "true"
  }
}

module "eg_prod_bastion_abc_label" {
  source   = "github.com/vigetlabs/terraform-context.git"
  # We recommend pinning every module to a specific version
  # source = "github.com/vigetlabs/terraform-context.git?ref=vx.x.x"

  attributes = ["abc"]

  tags = {
    "BusinessUnit" = "ABC" # Override the Business Unit tag set in the base label
  }

  # Copy all other fields from the base label
  context = module.eg_prod_bastion_label.context
}

resource "aws_security_group" "eg_prod_bastion_abc" {
  name = module.eg_prod_bastion_abc_label.id
  tags = module.eg_prod_bastion_abc_label.tags
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "eg_prod_bastion_abc" {
   instance_type          = "t1.micro"
   tags                   = module.eg_prod_bastion_abc_label.tags
   vpc_security_group_ids = [aws_security_group.eg_prod_bastion_abc.id]
}

module "eg_prod_bastion_xyz_label" {
  source   = "github.com/vigetlabs/terraform-context.git"
  # We recommend pinning every module to a specific version
  # source = "github.com/vigetlabs/terraform-context.git?ref=vx.x.x"

  attributes = ["xyz"]

  context = module.eg_prod_bastion_label.context
}

resource "aws_security_group" "eg_prod_bastion_xyz" {
  name = module.eg_prod_bastion_xyz_label.id
  tags = module.eg_prod_bastion_xyz_label.tags
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "eg_prod_bastion_xyz" {
   instance_type          = "t1.micro"
   tags                   = module.eg_prod_bastion_xyz_label.tags
   vpc_security_group_ids = [aws_security_group.eg_prod_bastion_xyz.id]
}
```

</details>

### Advanced Example 2

Here is a more complex example with an autoscaling group that has a different tagging schema than other resources and
requires its tags to be in this format, which this module can generate via `additional_tag_map` and `tags_as_list_of_maps`:

<details><summary>Click to show</summary>

```hcl
tags = [
    {
        key = "Name",
        propagate_at_launch = true,
        value = "namespace-stage-name"
    },
    {
        key = "Namespace",
        propagate_at_launch = true,
        value = "namespace"
    },
    {
        key = "Stage",
        propagate_at_launch = true,
        value = "stage"
    }
]
```

Autoscaling group using propagating tagging below (full example: [autoscalinggroup](examples/autoscalinggroup/main.tf))

```hcl
################################
# terraform-context example #
################################
module "label" {
  source    = "../../"
  namespace = "cp"
  stage     = "prod"
  name      = "app"

  tags = {
    BusinessUnit = "Finance"
    ManagedBy    = "Terraform"
  }

  additional_tag_map = {
    propagate_at_launch = true
  }
}

#######################
# Launch template     #
#######################
resource "aws_launch_template" "default" {
  # terraform-context example used here: Set template name prefix
  name_prefix                           = "${module.label.id}-"
  image_id                              = data.aws_ami.amazon_linux.id
  instance_type                         = "t2.micro"
  instance_initiated_shutdown_behavior  = "terminate"

  vpc_security_group_ids                = [data.aws_security_group.default.id]

  monitoring {
    enabled                             = false
  }
  # terraform-context example used here: Set tags on volumes
  tag_specifications {
    resource_type                       = "volume"
    tags                                = module.label.tags
  }
}

######################
# Autoscaling group  #
######################
resource "aws_autoscaling_group" "default" {
  # terraform-context example used here: Set ASG name prefix
  name_prefix                           = "${module.label.id}-"
  vpc_zone_identifier                   = data.aws_subnet_ids.all.ids
  max_size                              = 1
  min_size                              = 1
  desired_capacity                      = 1

  launch_template = {
    id                                  = aws_launch_template.default.id
    version                             = "$$Latest"
  }

  # terraform-context example used here: Set tags on ASG and EC2 Servers
  tags                                  = module.label.tags_as_list_of_maps
}
```

</details>

### Advanced Example 3

This example shows how you can pass the `context` output of one label module to the next label_module,
allowing you to create one label that has the base set of values, and then creating every extra label
as a derivative of that.

<details><summary>Click to show</summary>

```hcl
module "label1" {
  source   = "github.com/vigetlabs/terraform-context.git"
  # We recommend pinning every module to a specific version
  # source = "github.com/vigetlabs/terraform-context.git?ref=vx.x.x"

  namespace   = "Viget"
  tenant      = "H.R.H"
  environment = "UAT"
  stage       = "build"
  name        = "Winston"
  attributes  = ["fire", "water", "earth", "air"]

  label_order = ["name", "tenant", "environment", "stage", "attributes"]

  tags = {
    "City"        = "Dublin"
    "Environment" = "Private"
  }
}

module "label2" {
  source   = "github.com/vigetlabs/terraform-context.git"
  # We recommend pinning every module to a specific version
  # source = "github.com/vigetlabs/terraform-context.git?ref=vx.x.x"

  name      = "Charlie"
  tenant    = "" # setting to `null` would have no effect
  stage     = "test"
  delimiter = "+"
  regex_replace_chars = "/[^a-zA-Z0-9-+]/"

  additional_tag_map = {
    propagate_at_launch = true
    additional_tag      = "yes"
  }

  tags = {
    "City"        = "London"
    "Environment" = "Public"
  }

  context   = module.label1.context
}

module "label3" {
  source   = "github.com/vigetlabs/terraform-context.git"
  # We recommend pinning every module to a specific version
  # source = "github.com/vigetlabs/terraform-context.git?ref=vx.x.x"

  name      = "Starfish"
  stage     = "release"
  delimiter = "."
  regex_replace_chars = "/[^-a-zA-Z0-9.]/"

  tags = {
    "Eat"    = "Carrot"
    "Animal" = "Rabbit"
  }

  context   = module.label1.context
}
```

This creates label outputs like this:

```hcl
label1 = {
  "attributes" = tolist([
    "fire",
    "water",
    "earth",
    "air",
  ])
  "delimiter" = "-"
  "id" = "winston-hrh-uat-build-fire-water-earth-air"
  "name" = "winston"
  "namespace" = "viget"
  "stage" = "build"
  "tenant" = "hrh"
}

label1_context = {
  "additional_tag_map" = {}
  "attributes" = tolist([
    "fire",
    "water",
    "earth",
    "air",
  ])
  "delimiter" = tostring(null)
  "enabled" = true
  "environment" = "UAT"
  "id_length_limit" = tonumber(null)
  "label_key_case" = tostring(null)
  "label_order" = tolist([
    "name",
    "tenant",
    "environment",
    "stage",
    "attributes",
  ])
  "label_value_case" = tostring(null)
  "name" = "Winston"
  "namespace" = "Viget"
  "regex_replace_chars" = tostring(null)
  "stage" = "build"
  "tags" = {
    "City" = "Dublin"
    "Environment" = "Private"
  }
  "tenant" = "H.R.H"
}
label1_normalized_context = {
  "additional_tag_map" = {}
  "attributes" = tolist([
    "fire",
    "water",
    "earth",
    "air",
  ])
  "delimiter" = "-"
  "enabled" = true
  "environment" = "uat"
  "id_length_limit" = 0
  "label_key_case" = "title"
  "label_order" = tolist([
    "name",
    "tenant",
    "environment",
    "stage",
    "attributes",
  ])
  "label_value_case" = "lower"
  "name" = "winston"
  "namespace" = "viget"
  "regex_replace_chars" = "/[^-a-zA-Z0-9]/"
  "stage" = "build"
  "tags" = {
    "Attributes" = "fire-water-earth-air"
    "City" = "Dublin"
    "Environment" = "Private"
    "Name" = "winston-hrh-uat-build-fire-water-earth-air"
    "Namespace" = "viget"
    "Stage" = "build"
    "Tenant" = "hrh"
  }
  "tenant" = "hrh"
}
label1_tags = tomap({
  "Attributes" = "fire-water-earth-air"
  "City" = "Dublin"
  "Environment" = "Private"
  "Name" = "winston-hrh-uat-build-fire-water-earth-air"
  "Namespace" = "viget"
  "Stage" = "build"
  "Tenant" = "hrh"
})
label2 = {
  "attributes" = tolist([
    "fire",
    "water",
    "earth",
    "air",
  ])
  "delimiter" = "+"
  "id" = "charlie+uat+test+fire+water+earth+air"
  "name" = "charlie"
  "namespace" = "viget"
  "stage" = "test"
  "tenant" = ""
}
label2_context = {
  "additional_tag_map" = {
    "additional_tag" = "yes"
    "propagate_at_launch" = "true"
  }
  "attributes" = tolist([
    "fire",
    "water",
    "earth",
    "air",
  ])
  "delimiter" = "+"
  "enabled" = true
  "environment" = "UAT"
  "id_length_limit" = tonumber(null)
  "label_key_case" = tostring(null)
  "label_order" = tolist([
    "name",
    "tenant",
    "environment",
    "stage",
    "attributes",
  ])
  "label_value_case" = tostring(null)
  "name" = "Charlie"
  "namespace" = "Viget"
  "regex_replace_chars" = "/[^a-zA-Z0-9-+]/"
  "stage" = "test"
  "tags" = {
    "City" = "London"
    "Environment" = "Public"
  }
  "tenant" = ""
}
label2_tags = tomap({
  "Attributes" = "fire+water+earth+air"
  "City" = "London"
  "Environment" = "Public"
  "Name" = "charlie+uat+test+fire+water+earth+air"
  "Namespace" = "viget"
  "Stage" = "test"
})
label2_tags_as_list_of_maps = [
  {
    "additional_tag" = "yes"
    "key" = "Attributes"
    "propagate_at_launch" = "true"
    "value" = "fire+water+earth+air"
  },
  {
    "additional_tag" = "yes"
    "key" = "City"
    "propagate_at_launch" = "true"
    "value" = "London"
  },
  {
    "additional_tag" = "yes"
    "key" = "Environment"
    "propagate_at_launch" = "true"
    "value" = "Public"
  },
  {
    "additional_tag" = "yes"
    "key" = "Name"
    "propagate_at_launch" = "true"
    "value" = "charlie+uat+test+fire+water+earth+air"
  },
  {
    "additional_tag" = "yes"
    "key" = "Namespace"
    "propagate_at_launch" = "true"
    "value" = "viget"
  },
  {
    "additional_tag" = "yes"
    "key" = "Stage"
    "propagate_at_launch" = "true"
    "value" = "test"
  },
]
label3 = {
  "attributes" = tolist([
    "fire",
    "water",
    "earth",
    "air",
  ])
  "delimiter" = "."
  "id" = "starfish.h.r.h.uat.release.fire.water.earth.air"
  "name" = "starfish"
  "namespace" = "viget"
  "stage" = "release"
  "tenant" = "h.r.h"
}
label3_context = {
  "additional_tag_map" = {}
  "attributes" = tolist([
    "fire",
    "water",
    "earth",
    "air",
  ])
  "delimiter" = "."
  "enabled" = true
  "environment" = "UAT"
  "id_length_limit" = tonumber(null)
  "label_key_case" = tostring(null)
  "label_order" = tolist([
    "name",
    "tenant",
    "environment",
    "stage",
    "attributes",
  ])
  "label_value_case" = tostring(null)
  "name" = "Starfish"
  "namespace" = "Viget"
  "regex_replace_chars" = "/[^-a-zA-Z0-9.]/"
  "stage" = "release"
  "tags" = {
    "Animal" = "Rabbit"
    "City" = "Dublin"
    "Eat" = "Carrot"
    "Environment" = "Private"
  }
  "tenant" = "H.R.H"
}
label3_normalized_context = {
  "additional_tag_map" = {}
  "attributes" = tolist([
    "fire",
    "water",
    "earth",
    "air",
  ])
  "delimiter" = "."
  "enabled" = true
  "environment" = "uat"
  "id_length_limit" = 0
  "label_key_case" = "title"
  "label_order" = tolist([
    "name",
    "tenant",
    "environment",
    "stage",
    "attributes",
  ])
  "label_value_case" = "lower"
  "name" = "starfish"
  "namespace" = "viget"
  "regex_replace_chars" = "/[^-a-zA-Z0-9.]/"
  "stage" = "release"
  "tags" = {
    "Animal" = "Rabbit"
    "Attributes" = "fire.water.earth.air"
    "City" = "Dublin"
    "Eat" = "Carrot"
    "Environment" = "Private"
    "Name" = "starfish.h.r.h.uat.release.fire.water.earth.air"
    "Namespace" = "viget"
    "Stage" = "release"
    "Tenant" = "h.r.h"
  }
  "tenant" = "h.r.h"
}
label3_tags = tomap({
  "Animal" = "Rabbit"
  "Attributes" = "fire.water.earth.air"
  "City" = "Dublin"
  "Eat" = "Carrot"
  "Environment" = "Private"
  "Name" = "starfish.h.r.h.uat.release.fire.water.earth.air"
  "Namespace" = "viget"
  "Stage" = "release"
  "Tenant" = "h.r.h"
})

```

</details>

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.13.0 |

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br>This is for some rare cases where resources want additional configuration of tags<br>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br>in the order they appear in the list. New attributes are appended to the<br>end of the list. The elements of the list are joined by the `delimiter`<br>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_component"></a> [component](#input\_component) | ID element. Usually the component or solution name, e.g. 'eks', 'rds', 'app'. | `string` | `null` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br>See description of individual variables for details.<br>Leave string and numeric variables as `null` to use default value.<br>Individual variable settings (non-null) override settings in context object,<br>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br>  "additional_tag_map": {},<br>  "attributes": [],<br>  "component": null,<br>  "delimiter": null,<br>  "descriptor_formats": {},<br>  "enabled": true,<br>  "id_length_limit": null,<br>  "label_key_case": null,<br>  "label_order": [],<br>  "label_value_case": null,<br>  "labels_as_tags": [<br>    "unset"<br>  ],<br>  "namespace": null,<br>  "regex_replace_chars": null,<br>  "tags": {},<br>  "tenant": null<br>}</pre> | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br>Map of maps. Keys are names of descriptors. Values are maps of the form<br>`{<br>   format = string<br>   labels = list(string)<br>}`<br>(Type is `any` so the map values can later be enhanced to provide additional options.)<br>`format` is a Terraform format string to be passed to the `format()` function.<br>`labels` is a list of labels, in order, to pass to `format()` function.<br>Label values will be normalized before being passed to `format()` so they will be<br>identical to how they appear in `id`.<br>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br>Set to `0` for unlimited length.<br>Set to `null` for keep the existing setting, which defaults to `0`.<br>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br>Does not affect keys of tags passed in via the `tags` input.<br>Possible values: `lower`, `title`, `upper`.<br>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br>Defaults to ["namespace", "stage", "component", "attributes"].<br>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br>set as tag values, and output by this module individually.<br>Does not affect values of tags passed in via the `tags` input.<br>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br>Default is to include all labels.<br>Tags with empty values will not be included in the `tags` output.<br>Set to `[]` to suppress all generated tags.<br>**Notes:**<br>  The value of the `name` tag, if included, will be the `id`.<br>  Unlike other `context` inputs, the initial setting of `labels_as_tags` cannot be<br>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br>  "default"<br>]</pre> | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of the organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br>Characters matching the regex will be removed from the ID elements.<br>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_additional_tag_map"></a> [additional\_tag\_map](#output\_additional\_tag\_map) | The merged additional\_tag\_map |
| <a name="output_attributes"></a> [attributes](#output\_attributes) | List of attributes |
| <a name="output_component"></a> [component](#output\_component) | Normalized component |
| <a name="output_context"></a> [context](#output\_context) | Merged but otherwise unmodified input to this module, to be used as context input to other modules.<br>Note: this version will have null values as defaults, not the values actually used as defaults. |
| <a name="output_delimiter"></a> [delimiter](#output\_delimiter) | Delimiter between `namespace`, `tenant`, `component`, and `attributes` |
| <a name="output_descriptors"></a> [descriptors](#output\_descriptors) | Map of descriptors as configured by `descriptor_formats` |
| <a name="output_enabled"></a> [enabled](#output\_enabled) | True if module is enabled, false otherwise |
| <a name="output_id"></a> [id](#output\_id) | Disambiguated ID string restricted to `id_length_limit` characters in total |
| <a name="output_id_full"></a> [id\_full](#output\_id\_full) | ID string not restricted in length |
| <a name="output_id_length_limit"></a> [id\_length\_limit](#output\_id\_length\_limit) | The id\_length\_limit actually used to create the ID, with `0` meaning unlimited |
| <a name="output_label_order"></a> [label\_order](#output\_label\_order) | The naming order actually used to create the ID |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Normalized namespace |
| <a name="output_normalized_context"></a> [normalized\_context](#output\_normalized\_context) | Normalized context of this module |
| <a name="output_regex_replace_chars"></a> [regex\_replace\_chars](#output\_regex\_replace\_chars) | The regex\_replace\_chars actually used to create the ID |
| <a name="output_tags"></a> [tags](#output\_tags) | Normalized Tag map |
| <a name="output_tags_as_list_of_maps"></a> [tags\_as\_list\_of\_maps](#output\_tags\_as\_list\_of\_maps) | This is a list with one map for each `tag`. Each map contains the tag `key`,<br>`value`, and contents of `var.additional_tag_map`. Used in the rare cases<br>where resources need additional configuration information for each tag. |
| <a name="output_tenant"></a> [tenant](#output\_tenant) | Normalized tenant |
<!-- END_TF_DOCS -->

Contributors
-----

Nevin Morgan<br/>Viget Labs<br/>https://www.viget.com

See the [upstream repository](https://github.com/cloudposse/terraform-null-label#contributors) for a full list of contributors
