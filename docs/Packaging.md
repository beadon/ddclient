# Packaging

Author: [@beadon](https://github.com/beadon)\
Date: 2026-05-05

This document describes how ddclient is packaged for Linux distributions
and how the packaging workflow operates.

## Automated packaging

A GitHub Actions workflow (`.github/workflows/package-rpm.yml`) builds and
publishes distribution packages automatically whenever a release is published
on GitHub. It is also triggerable manually via `workflow_dispatch` for
testing.

On each run the workflow:

1. Checks out the source at the release tag.
2. Builds the distribution tarball using the autotools build system
   (`./autogen && ./configure && make dist`).
3. Builds a binary RPM and a source RPM (SRPM) inside a Fedora container
   for each supported Fedora release.
4. Attaches all RPMs to the GitHub release as downloadable assets.

## Supported distributions

| Distribution | Builds produced       |
|--------------|-----------------------|
| Fedora 42    | noarch RPM + SRPM     |
| Fedora 43    | noarch RPM + SRPM     |
| Fedora 44    | noarch RPM + SRPM     |
| Fedora rawhide | noarch RPM + SRPM   |

The matrix in `.github/workflows/package-rpm.yml` should be updated each time a new Fedora
release reaches stable and an old one reaches end-of-life. See
<https://endoflife.date/fedora> for the current support window.

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
(see the comment block in `ddclient.in` near `$VERSION`), but the packaging
workflow will handle any future suffix without modification.

## Building an RPM locally

Install the required tools on a Fedora system:

```sh
sudo dnf install -y automake curl findutils make rpm-build systemd-rpm-macros \
    perl-interpreter perl-Data-Dumper perl-File-Path perl-Getopt-Long \
    perl-Socket perl-Sys-Hostname perl-version
```

Build the distribution tarball and the RPMs:

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

Add the new image to the `fedora_version` matrix in
`.github/workflows/package-rpm.yml`. No changes to the spec file are
needed.

### Other package formats (Debian, Arch, etc.)

Add a new spec or build file under `packaging/<format>/` and a
corresponding workflow under `.github/workflows/package-<format>.yml`,
following the same pattern as the RPM workflow:

- Derive the version from the distribution tarball produced by `make dist`.
- Pass version components to the build tool rather than hardcoding them.
- Use `softprops/action-gh-release` to attach built packages to the release.
