# Packaging

Author: [@beadon](https://github.com/beadon)\
Date: 2026-05-05

This document describes how ddclient is packaged for Linux distributions
and how the packaging workflow operates.

## Automated packaging

A GitHub Actions workflow ([`.github/workflows/package-rpm.yml`](../.github/workflows/package-rpm.yml)) builds and
publishes distribution packages automatically whenever a release is published
on GitHub. It is also triggerable manually via `workflow_dispatch` for
testing.

On each run the workflow:

1. Checks out the source at the release tag.
2. Builds the distribution tarball using the autotools build system
   (`./autogen && ./configure && make dist`).
3. Builds a binary RPM and a source RPM (SRPM) in parallel across two jobs:
   - `build-fedora` — runs inside `fedora:N` containers for each supported Fedora release
   - `build-epel` — runs inside `almalinux:N` containers with EPEL and CRB/powertools enabled, for each supported EPEL release
4. Attaches all RPMs to the GitHub release as downloadable assets.

### Manual dispatch

The workflow can also be triggered manually without publishing a release,
which is useful for testing packaging changes on a branch before cutting a
release.

**Via the GitHub UI:**

1. Go to **Actions → Package RPM** on GitHub.
2. Click **Run workflow**, select the branch to build from, and click
   **Run workflow**.

**Via the `gh` CLI:**

```sh
# Run against the default branch
gh workflow run package-rpm.yml --repo ddclient/ddclient

# Run against a specific branch or tag
gh workflow run package-rpm.yml --repo ddclient/ddclient --ref my-branch
```

When triggered this way the RPMs are built and uploaded as workflow
artifacts (visible in the Actions run summary) but are **not** attached to
any release. The version is derived from whatever `make dist` produces on
the selected branch.

## Creating a release

Publishing a release on GitHub (i.e. not a draft) automatically triggers
the packaging workflow and attaches the resulting RPMs to the release.

### Via the GitHub UI

1. Go to **Releases → Draft a new release** on GitHub.
2. Enter the tag (e.g. `v4.0.1-rc.1` or `v4.0.1`) and title.
3. Write the release notes.
4. For a pre-release (alpha, beta, rc), check **Set as a pre-release**.
5. Click **Publish release**.

### Via the `gh` CLI

**Pre-release (alpha, beta, rc):**

```sh
gh release create v4.0.1-rc.1 \
  --repo ddclient/ddclient \
  --title "v4.0.1-rc.1" \
  --notes "Release candidate 1 for v4.0.1." \
  --prerelease
```

**Final release:**

```sh
gh release create v4.0.1 \
  --repo ddclient/ddclient \
  --title "v4.0.1" \
  --notes-from-tag
```

`--notes-from-tag` uses the annotated git tag message as the release notes.
To write notes inline use `--notes "..."` or `--notes-file changelog.md`
instead.

### Verifying the release artifacts

After the workflow completes, the RPM artifacts are attached to the release
and visible at:

```
https://github.com/ddclient/ddclient/releases/tag/v4.0.1-rc.1
```

To download and install a specific RPM to verify it:

```sh
# Fedora 44
curl -fsSL -O https://github.com/ddclient/ddclient/releases/download/v4.0.1-rc.1/ddclient-4.0.1-0.1.rc.1.fc44.noarch.rpm
sudo dnf install -y ./ddclient-4.0.1-0.1.rc.1.fc44.noarch.rpm
ddclient --version

# EPEL 9 (RHEL/AlmaLinux/Rocky 9)
curl -fsSL -O https://github.com/ddclient/ddclient/releases/download/v4.0.1-rc.1/ddclient-4.0.1-0.1.rc.1.el9.noarch.rpm
sudo dnf install -y ./ddclient-4.0.1-0.1.rc.1.el9.noarch.rpm
ddclient --version
```

## Supported distributions

| Distribution | Container | Builds produced | EOL |
|---|---|---|---|
| Fedora 42 | `fedora:42` | noarch RPM + SRPM | 2026-05-27 |
| Fedora 43 | `fedora:43` | noarch RPM + SRPM | 2026-12-09 |
| Fedora 44 | `fedora:44` | noarch RPM + SRPM | 2027-06-02 |
| Fedora rawhide | `fedora:rawhide` | noarch RPM + SRPM | rolling |
| EPEL 8 (RHEL/AlmaLinux 8) | `almalinux:8` | noarch RPM + SRPM | 2029-03-01 |
| EPEL 9 (RHEL/AlmaLinux 9) | `almalinux:9` | noarch RPM + SRPM | 2032-05-31 |
| EPEL 10 (RHEL/AlmaLinux 10) | `almalinux:10` | noarch RPM + SRPM | 2035-05-31 |

The matrices in [`.github/workflows/package-rpm.yml`](../.github/workflows/package-rpm.yml) should be updated when Fedora releases
reach stable or end-of-life. See <https://endoflife.date/fedora> for Fedora
and <https://endoflife.date/almalinux> for EPEL/RHEL support windows.

## Version translation

ddclient uses [Semantic Versioning 2.0.0](https://semver.org/) with a
pre-release suffix separated by `-` and a post-release suffix separated by
`+`. RPM forbids `-` in the `Version:` field, so the version is split at
the boundary and the suffix is moved into `Release:`.

| ddclient version | RPM `Version:` | RPM `Release:`         |
|------------------|----------------|------------------------|
| `4.0.0`          | `4.0.0`        | `1%{?dist}`            |
| `4.0.1-alpha`    | `4.0.1`        | `0.1.alpha%{?dist}`    |
| `4.0.1-beta.2`   | `4.0.1`        | `0.1.beta.2%{?dist}`   |
| `4.0.1-rc.3`     | `4.0.1`        | `0.1.rc.3%{?dist}`     |
| `4.0.1+r.2`      | `4.0.1`        | `1.r.2%{?dist}`        |

Pre-release versions (leading `0.` in `Release:`) sort before the final
release. Post-release versions sort after. This follows the
[Fedora packaging versioning guidelines](https://docs.fedoraproject.org/en-US/packaging-guidelines/Versioning/).

The workflow does not validate or restrict the suffix — any string after
`-` is treated as a pre-release label and any string after `+` is treated
as a post-release label, passed through verbatim into `Release:`. The
examples above reflect the suffixes defined by ddclient's versioning scheme
(see the comment block in [`ddclient.in`](../ddclient.in) near `$VERSION`), but the packaging
workflow will handle any future suffix without modification.

## Building an RPM locally

**On Fedora:**

```sh
sudo dnf install -y automake curl findutils make rpm-build systemd-rpm-macros \
    perl-interpreter perl-Data-Dumper perl-File-Path perl-Getopt-Long \
    perl-Socket perl-Sys-Hostname perl-version
```

**On EPEL (RHEL/AlmaLinux/Rocky):** enable EPEL and CRB first, then install
with `--skip-broken` since some Perl modules are bundled into `perl-core`
rather than shipped as separate packages:

```sh
sudo dnf install -y 'dnf-command(config-manager)' epel-release
sudo dnf config-manager --set-enabled crb   # use 'powertools' on el8
sudo dnf install --skip-broken -y automake curl findutils make perl-core \
    rpm-build systemd-rpm-macros perl-interpreter perl-Data-Dumper \
    perl-File-Path perl-Getopt-Long perl-Socket perl-Sys-Hostname perl-version
```

Build the distribution tarball and the RPMs using [`packaging/rpm/ddclient.spec`](../packaging/rpm/ddclient.spec):

```sh
./autogen
./configure
make dist

TOPDIR="$(pwd)/rpmbuild"
mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

TARBALL=$(ls ddclient-*.tar.gz)
UPSTREAM="${TARBALL#ddclient-}"; UPSTREAM="${UPSTREAM%.tar.gz}"

case "$UPSTREAM" in
  *-*) RPM_VERSION="${UPSTREAM%%-*}"; LABEL="${UPSTREAM#*-}"; RPM_RELEASE="0.1.${LABEL}%{?dist}" ;;
  *+*) RPM_VERSION="${UPSTREAM%%+*}"; LABEL="${UPSTREAM#*+}"; RPM_RELEASE="1.${LABEL}%{?dist}" ;;
  *)   RPM_VERSION="$UPSTREAM"; RPM_RELEASE="1%{?dist}" ;;
esac

cp "$TARBALL" "$TOPDIR/SOURCES/"
cp packaging/rpm/ddclient.spec "$TOPDIR/SPECS/"

rpmbuild \
  --define "_topdir $TOPDIR" \
  --define "upstream_version ${UPSTREAM}" \
  --define "rpm_version ${RPM_VERSION}" \
  --define "rpm_release ${RPM_RELEASE}" \
  -ba "$TOPDIR/SPECS/ddclient.spec"
```

The resulting RPMs will be in `rpmbuild/RPMS/` and `rpmbuild/SRPMS/`.

## Adding a new distribution

### RPM-based (Fedora, AlmaLinux, RHEL)

For a new **Fedora** release, add the version number to the `fedora_version`
matrix in the `build-fedora` job in
[`.github/workflows/package-rpm.yml`](../.github/workflows/package-rpm.yml).

For a new **EPEL** release (RHEL/AlmaLinux/Rocky), add the major version to
the `epel_version` matrix in the `build-epel` job. No changes to the spec
file are needed in either case.

### Other package formats (Debian, Arch, etc.)

Add a new spec or build file under `packaging/<format>/` and a
corresponding workflow under `.github/workflows/package-<format>.yml`,
following the same pattern as the RPM workflow:

- Derive the version from the distribution tarball produced by `make dist`.
- Pass version components to the build tool rather than hardcoding them.
- Use `softprops/action-gh-release` to attach built packages to the release.
