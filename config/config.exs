import Config

config :versioce,
  post_hooks: [Versioce.PostHooks.Git.Release]

config :versioce, :git,
  tag_template: "v{version}",
  tag_message_template: "Release v{version}",
  commit_message_template: "Bump version to {version}"
