# Shuttle `fastlane` plugin

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-shuttle) [![Gem Version](https://badge.fury.io/rb/fastlane-plugin-shuttle.svg)](https://badge.fury.io/rb/fastlane-plugin-shuttle)

## Getting Started

This project is a [_fastlane_](https://github.com/fastlane/fastlane) plugin. To get started with `fastlane-plugin-shuttle`, add it to your project by running:

```bash
fastlane add_plugin shuttle
```

## About Shuttle

Publish your builds on your [Shuttle.tools](https://shuttle.tools) instance

This plugin provides a `shuttle` action which allows you to upload and distribute your apps to your testers via your Shuttle instance interface.

## Usage

To get started, first, [obtain an API access token](https://docs.shuttle.tools/admin-guide/) in your Shuttle instance admin section. The API Access Token is used to authenticate with the Shuttle API in each call.

```ruby
url = shuttle(
      access_token: <shuttle access token>,
      package_path: <path to your IPA or APK binary file>,
      release_name: <release name displayed in shuttle>,
      release_notes: <release notes>,
      base_url: "https://<your instance name>.shuttle.tools/")
```

The action parameters `access_token` can be omitted when its value is [set as environment variables](https://docs.fastlane.tools/advanced/#environment-variables). Below a list of all available environment variables:

- `SHUTTLE_ACCESS_TOKEN` - API Access Token for Shuttle API
- `SHUTTLE_BASE_URL` - Shuttle instance URL (eg. https://<your instance name>.shuttle.tools/)
- `SHUTTLE_RELEASE_NAME` - The name of the release (eg. MyApp v3)
- `SHUTTLE_PACKAGE_PATH` - Build release path for android or ios build (if not provided, it'll check in shared values `GRADLE_APK_OUTPUT_PATH` or `IPA_OUTPUT_PATH`)
- `SHUTTLE_ENV_ID` - The uniq ID of the app's environment you want to publish the build to (if not provided, it will try to guess it or ask to select/create it interactively then display the value so you can set it definitively)
- `SHUTTLE_RELEASE_NOTES` - Release notes

## Example

Check out the [example `Fastfile`](fastlane/Fastfile) to see how to use this plugin. Try it by cloning the repo, running `fastlane install_plugins` and `bundle exec fastlane test`.

## Run tests for this plugin

To run both the tests, and code style validation, run

```
rake
```

To automatically fix many of the styling issues, use
```
rubocop -a
```

## Issues and Feedback

For any other issues and feedback about this plugin, please submit it to this repository.

## Troubleshooting

If you have trouble using plugins, check out the [Plugins Troubleshooting](https://docs.fastlane.tools/plugins/plugins-troubleshooting/) guide.

## Using _fastlane_ Plugins

For more information about how the `fastlane` plugin system works, check out the [Plugins documentation](https://docs.fastlane.tools/plugins/create-plugin/).

## About _fastlane_

_fastlane_ is the easiest way to automate beta deployments and releases for your iOS and Android apps. To learn more, check out [fastlane.tools](https://fastlane.tools).
