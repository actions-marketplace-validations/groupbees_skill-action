# skill-action

A GitHub Action that checks a repository of Agent Skills: every skill must
pass [skill-validator](https://github.com/agent-ecosystem/skill-validator), and
[pollen](https://github.com/groupbees/pollen) must be able to deploy them
(`pollen validate`).

## Description

The action installs both tools from their GitHub Releases, at the versions you
ask for or the latest ones, and refuses any archive whose SHA-256 does not
check out. Then it runs:

- `skill-validator check` on each skill under `skills-path`, with inline
  annotations on the pull request diff and a Markdown report in the job
  summary;
- `pollen validate` on a throwaway `pollen.yaml` that selects every skill under
  `skills-path` (`repo: local`, `recurse: true`), which is what a consumer's
  `pollen update` validates before deploying them.

Both checks run even when the other one fails, so one run reports every
problem.

## Getting started

### Prerequisites

- A Linux or macOS runner, x86-64 or ARM64. Windows runners are not supported.
- `gh` on the runner's `PATH`, which every GitHub-hosted runner has.

### Usage

```yaml
jobs:
  skills:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - uses: groupbees/skill-action@<commit-sha>
        with:
          skills-path: skills
```

Pin the action to a full commit SHA, as any third-party action.

To pin the tools as well, set their versions and the SHA-256 of their archives
for the runner's platform:

```yaml
      - uses: groupbees/skill-action@<commit-sha>
        with:
          skill-validator-version: v1.8.0
          skill-validator-sha256: a9b4cb3436682ff8d55dd0d164376c8479d35cb58c0adc3e93170fbde8baa04f
          pollen-version: v0.6.0
          pollen-sha256: 25aafb729024e4bf54db7d01896631cf769f3dbf9baaca6a87d47d2965001bd3
```

Those two hashes are the `linux_amd64` and `x86_64-unknown-linux-musl`
archives, for `ubuntu-24.04`. Each run without a pinned hash prints the one it
installed as a notice, ready to copy.

### Inputs

| Input | Default | Description |
| --- | --- | --- |
| `skills-path` | `skills` | Directory holding the skills, relative to the working directory. |
| `strict` | `true` | Fail on skill-validator warnings, not only on errors. |
| `allow-dirs` | — | Non-standard skill directories skill-validator accepts, comma-separated. |
| `skill-validator-version` | `latest` | Release to install (`v1.8.0` or `1.8.0`), or `latest`. |
| `skill-validator-sha256` | — | Expected SHA-256 of the skill-validator archive for the runner's platform. |
| `pollen-version` | `latest` | Release to install (`v0.6.0` or `0.6.0`), or `latest`. |
| `pollen-sha256` | — | Expected SHA-256 of the pollen archive for the runner's platform. |
| `github-token` | `${{ github.token }}` | Token used to read the releases through the GitHub API. |

### Outputs

| Output | Description |
| --- | --- |
| `skill-validator-version` | skill-validator release that was installed. |
| `pollen-version` | pollen release that was installed. |

### Download verification

Each archive is installed only when its SHA-256 matches, in this order:

1. the checksums file published in the same release;
2. the digest GitHub computed when the asset was uploaded;
3. the `*-sha256` input, when set.

The first two catch a corrupted or swapped download. Only the third protects
against a compromised release, whose author can rewrite both the archive and
its checksums file: pin it wherever that matters. A release whose asset has
no GitHub digest installs only with a pinned SHA-256.
