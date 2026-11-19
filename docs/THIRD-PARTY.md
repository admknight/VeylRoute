# Third-party components and distribution

VeylRoute includes original launcher, GUI and orchestration source under the project's [MIT License](../LICENSE). The tools it coordinates are independent software and **are not bundled in the source repository or the current GitHub Actions build artifacts**.

| Component | Official project / reference | Distribution policy |
| --- | --- | --- |
| Tor Windows Expert Bundle | [Tor Project](https://www.torproject.org/) | Installed/provisioned separately with signature checks |
| lyrebird / obfs4 | [Tor Project](https://www.torproject.org/) | Installed separately under its own terms |
| Wintun | [Wintun](https://www.wintun.net/) | Installed/provisioned separately |
| tun2socks | Upstream selected by VeylRoute's component provisioner | Installed/provisioned separately |
| Inno Setup | [JR Software](https://jrsoftware.org/isinfo.php) | Build-only installer compiler; not bundled as source |

Check upstream terms, license files, attribution requirements and authenticity before distributing third-party binaries. The project's MIT License grants rights only to VeylRoute's original material and does **not** automatically relicense upstream software. Code signing and trustworthy releases are separate concerns.
