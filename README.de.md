# setup-topgrade

[![ShellCheck](https://github.com/Pat9496/setup-topgrade/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Pat9496/setup-topgrade/actions/workflows/shellcheck.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)](https://www.kernel.org/)

Ein Bash-Skript, das [topgrade](https://github.com/topgrade-rs/topgrade) installiert und konfiguriert — das Werkzeug, das alle Aktualisierungsbefehle des Systems (apt/dnf/flatpak/cargo/firmware/etc.) in einem Schritt ausführt — auf jedem Linux-System, einschließlich OSTree-basierter atomarer und unveränderlicher Systeme wie Bazzite und Fedora Silverblue/Kinoite/Atomic sowie bootc-basierten atomaren Hosts.

[English version](README.md)

## Inhaltsverzeichnis

- [Features](#features)
- [Anforderungen](#anforderungen)
- [Verwendung](#verwendung)
- [Funktionsweise](#funktionsweise)
- [Fedora-Atomic--Kinoite-Installationsmethoden](#fedora-atomic--kinoite-installationsmethoden)
- [Konfiguration](#konfiguration)
- [Quellen](#quellen)
- [Lizenz](#lizenz)

## Features

- **Funktioniert auf verschiedenen Distributionen.** Verwendet die dokumentierte Installationsmethode für topgrade jeder Distribution, sofern vorhanden (Fedora/RHEL über COPR auf klassischen Hosts, Alpine über `apk`, Void über `xbps-install`, Homebrew/Linuxbrew), und lädt ansonsten die vorkompilierte Binärdatei von GitHub Releases in `~/.local/bin` herunter.
- **Gibt Fedora-Atomic-Nutzern eine klare Wahl.** Auf rpm-ostree-Hosts (Bazzite, Fedora Silverblue/Kinoite/Atomic) kann entweder die COPR/rpm-ostree-Paketintegration oder die offizielle Upstream-Binärdatei gewählt werden. Auf reinen bootc-Atomic-Hosts wird die Binärmethode verwendet.
- **Härtet beide Atomic-Pfade.** Der COPR-Pfad beschränkt das hinzugefügte `lilay/topgrade`-Repo mit `includepkgs=topgrade`; der GitHub-Release-Pfad wählt das erwartete Linux-Asset aus den Release-Metadaten, verifiziert den von GitHub bereitgestellten SHA-256-Digest, sofern vorhanden, testet `topgrade --version` und aktiviert die neue Binärdatei erst nach erfolgreicher Prüfung atomar.
- **Idempotent.** Kann sicher erneut ausgeführt werden. Bereits installiert? Das Skript springt direkt zur Konfiguration und Überprüfung. Bereits konfiguriert? Die Konfiguration wird nur mit `--force-config` neu erzeugt; kleine Installer-Policy-Reparaturen können mit zeitgestempeltem Backup angewendet werden.
- **Wird mit einer sinnvollen Standardkonfiguration ausgeliefert**, wobei einige Teile (siehe [Konfiguration](#konfiguration)) nur hinzugefügt werden, wenn sie für das System tatsächlich relevant sind.
- **Optionale [chezmoi](https://www.chezmoi.io/)-Integration.** Ist chezmoi installiert und initialisiert, wird die generierte Konfiguration automatisch unter chezmoi-Verwaltung gestellt.
- **Keine unerwarteten Überraschungen.** Dieses Skript soll interaktiv von einer Person ausgeführt werden. Das System wird nicht neu gestartet und bestehende Konfigurationen werden nicht überschrieben, ohne dass eine Bestätigung erfolgt.

## Anforderungen

- Bash
- `curl` oder `wget`
- `sudo`, falls nicht bereits als root läuft und ein privilegierter Installationsschritt erforderlich ist
- `python3`, zum sicheren Auswerten der GitHub-Release-Metadaten beim Installieren der Upstream-Binärdatei

## Verwendung

```bash
./install-topgrade.sh
```

Das Skript kann jederzeit erneut ausgeführt werden — es erkennt, was bereits abgeschlossen wurde, und setzt an der entsprechenden Stelle fort.

Auf Fedora Atomic / Kinoite kann die Installationsmethode explizit gewählt werden:

```bash
./install-topgrade.sh --install-method=binary
./install-topgrade.sh --install-method=copr
```

Zusätzlich gibt es Aliase:

```bash
./install-topgrade.sh --binary
./install-topgrade.sh --copr
```

Interaktive Atomic-Sitzungen fragen nach, wenn keine Methode angegeben wurde. Nicht-interaktive Atomic-Sitzungen verwenden standardmäßig die Binärmethode, weil sie keine Root-Rechte, kein Host-Paket-Layering und keinen Reboot benötigt.

Um eine bestimmte Upstream-Binärversion zu installieren:

```bash
./install-topgrade.sh --binary --version v17.9.0
```

oder `TOPGRADE_VERSION=v17.9.0` setzen.

## Funktionsweise

topgrade wird in den offiziellen Repositories von Fedora, RHEL oder AlmaLinux nicht paketiert. Auf klassischen Fedora/RHEL-Systemen kann dieses Skript topgrade aus [lilays `lilay/topgrade` COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) via `dnf` installieren. Auf Fedora-Atomic-Hosts unterstützt das Skript sowohl das COPR/rpm-ostree-Paketmodell als auch das offizielle Upstream-Binärmodell.

Das Skript wählt seine Installationsstrategie basierend auf dem erkannten System:

| System | Strategie |
|---|---|
| Bazzite, Fedora Silverblue/Kinoite/Atomic (`rpm-ostree` vorhanden) | Nachfrage oder explizites `--install-method`: COPR/rpm-ostree-Paketintegration oder Upstream-Binärdatei in `~/.local/bin/topgrade` |
| Atomarer Host ohne `rpm-ostree` (nur bootc) | Lädt die offizielle Upstream-Binärdatei von GitHub Releases nach `~/.local/bin/topgrade` |
| Fedora / RHEL / AlmaLinux (nicht-atomar) | Aktiviert das `lilay/topgrade`-COPR, installiert mit `dnf install` |
| Alpine | `apk add topgrade` |
| Void Linux | `xbps-install -Sy topgrade` |
| Homebrew / Linuxbrew vorhanden | `brew install topgrade` |
| Sonstige Systeme (Debian, Ubuntu, Arch, openSUSE oder falls eine native Methode fehlschlägt) | Lädt die neueste Release-Binärdatei von GitHub in `~/.local/bin/topgrade` herunter |

Privilegierte Schritte werden unter `sudo` ausgeführt. Läuft das Skript bereits als root, wird `sudo` übersprungen — dann ist das `sudo`-Binary nicht erforderlich.

## Fedora Atomic / Kinoite Installationsmethoden

Fedora-Atomic-Nutzer können zwischen zwei unterstützten Besitzmodellen wählen. Keine Methode ist grundsätzlich falsch; sie haben unterschiedliche Abwägungen.

| Thema | COPR / rpm-ostree | Upstream-Binärdatei |
|---|---|---|
| Installationsort | Host-Deployment (`/usr/bin/topgrade`) | `~/.local/bin/topgrade` |
| Root erforderlich | Ja | Nein |
| Reboot erforderlich | Ja | Nein |
| Fügt Drittanbieter-RPM-Repo hinzu | Ja, das spezifische `lilay/topgrade` COPR | Nein |
| Repo-Scope | Mit `includepkgs=topgrade` eingeschränkt, wo unterstützt | N/A |
| Topgrade-Updates | rpm-ostree | Eingebautes Self-Update von `topgrade-rs/topgrade` |
| Host-Paket-Layering | Ja | Nein |
| Paketmanager-Integration | Sehr gut | Keine |
| Einfache Deinstallation | `rpm-ostree uninstall topgrade` + Reboot | `~/.local/bin/topgrade` löschen |

Die COPR-Methode fügt das spezifische `lilay/topgrade`-Repository hinzu und installiert Topgrade als gelayertes RPM über rpm-ostree. Das aktiviert keine beliebigen COPR-Repositories. Der Installer beschränkt dieses Repository mit `includepkgs=topgrade` auf das Paket `topgrade`, aber man vertraut weiterhin dem Maintainer dieses COPR-Projekts für das Topgrade-RPM und dessen Updates.

Die Binärmethode installiert das offizielle Topgrade-Release direkt nach `~/.local/bin`, ohne ein RPM-Repository hinzuzufügen oder ein Paket ins Betriebssystem zu layern. Topgrade aktualisiert sich danach selbst aus den offiziellen `topgrade-rs/topgrade`-Upstream-Releases.

## Konfiguration

topgrade liest seine Konfiguration aus `${XDG_CONFIG_HOME:-~/.config}/topgrade.toml`. Existiert diese Datei noch nicht, erstellt das Skript eine. Bestehende Konfigurationen werden nur mit `--force-config` neu erzeugt, aber das Skript kann kleine Policy-Reparaturen mit zeitgestempeltem Backup vornehmen: zum Beispiel `rpm_ostree = true` auf Atomic-Hosts sicherstellen oder `no_self_update = true` auf `false` ändern, wenn Topgrade als user-lokale Upstream-Binärdatei installiert ist.

Die generierte Konfiguration enthält einige Teile bedingt, basierend darauf, was tatsächlich auf dem System vorhanden ist:

| Konfigurationsteil | Enthalten wenn |
|---|---|
| `[include] paths = ["/etc/ublue-os/topgrade.toml"]` | `/etc/ublue-os/topgrade.toml` existiert (ublue-os/Bazzite theme-update-Befehle) — da `~/.config/topgrade.toml` in `toolbx`/`distrobox`-Container eingebunden wird, kann dies dort einen harmlosen `Unable to read /etc/ublue-os/topgrade.toml`-Fehler protokollieren; das Skript gibt einen Hinweis aus, wenn es die Zeile hinzufügt |
| `[linux] rpm_ostree = true` | Wird auf einem atomaren Host ausgeführt, auf dem `rpm-ostree` verfügbar ist (hat Vorrang vor `bootc`) |
| `[linux] bootc = true` | Wird auf einem atomaren Host ausgeführt, auf dem `rpm-ostree` nicht verfügbar ist, aber `bootc` (reiner bootc-Host ohne anderen unterstützten Paketmanager) |
| `[misc] no_self_update = true` | topgrade wurde tatsächlich über einen Paketmanager installiert (`dnf`, COPR/rpm-ostree, `apk`, `xbps-install` oder Homebrew). Atomic-Binärinstallationen lassen Self-Update aktiviert |
| `"chezmoi"` in `disable`, `[misc] last = ["custom_commands"]`, plus ein `"Chezmoi Push"`-Befehl | chezmoi ist installiert und initialisiert |
| `"ScummVM Nightly"`-Befehl | `scummvm-nightly-update` ist in `$PATH` |
| `[containers] runtime = "podman"` | `podman` ist in `$PATH` und `docker` ist nicht |
| `"waydroid"` in `disable` | Wird hinzugefügt, falls waydroid nicht beide Bedingungen erfüllt: installiert **und** initialisiert (`waydroid status` meldet eine `Session:`-Zeile) |

> **Warum waydroid standardmäßig deaktiviert ist:** Falls waydroid installiert, aber nie initialisiert ist (`waydroid init` wurde nicht ausgeführt), gibt `waydroid status` keine `Session:`-Zeile aus, und topgrade stürzt ab, wenn es diese analysiert — ein Upstream-Fehler ([topgrade-rs/topgrade#869](https://github.com/topgrade-rs/topgrade/issues/869)). Um diesen Absturz zu vermeiden, deaktiviert das Skript den `waydroid`-Schritt, falls es die Initialisierung nicht bestätigen kann.
>
> Um topgrade waydroid verwalten zu lassen, `waydroid init` ausführen, dann `./install-topgrade.sh --force-config` erneut ausführen — das Skript erkennt die initialisierte Session und lässt `waydroid` aktiviert. (Alternativ kann `"waydroid"` in `disable = [...]` in `topgrade.toml` manuell gelöscht werden.)

### chezmoi-Integration

Ist [chezmoi](https://www.chezmoi.io/) installiert und initialisiert (d. h., `chezmoi init` wurde bereits ausgeführt), führt das Skript `chezmoi add` für die topgrade-Konfiguration aus, nachdem deren Existenz sichergestellt wurde — dies stellt sie unter chezmoi-Verwaltung, falls dies nicht bereits geschehen ist.

Das Skript deaktiviert dabei topgrades eingebauten `chezmoi`-Schritt (indem es `"chezmoi"` in `disable` aufnimmt) und ersetzt ihn durch einen eigenen `"Chezmoi Push"`-Befehl in `[commands]`. Dies dient zwei Zielen:

1. **Richtung/Sicherheit:** Der eingebaute `chezmoi`-Schritt in topgrade führt `chezmoi update` aus — ein reiner Pull+Apply-Vorgang, der Änderungen vom chezmoi-Remote automatisch und unbeaufsichtigt auf das lokale System anwendet. Das verstößt gegen das Designprinzip dieses Skripts (keine unerwarteten Überraschungen). Das Skript stellt stattdessen nur sicher, dass lokale Änderungen (insbesondere die neu generierte oder angepasste `topgrade.toml`) gesichert und zum Remote gepusht werden — ein Schreib-Vorgang, bei dem unerwünschte Überraschungen ausgeschlossen sind.
2. **Reihenfolge/Vollständigkeit:** Der benutzerdefinierte `"Chezmoi Push"`-Befehl wird durch `[misc] last = ["custom_commands"]` garantiert nach allen übrigen topgrade-Schritten ausgeführt. Dies stellt sicher, dass alle in diesem topgrade-Lauf angefallenen lokalen Änderungen in einem einzigen Commit erfasst werden. Der eingebaute `chezmoi`-Schritt hat in topgrade keine kontrollierbare Position relativ zu anderen Schritten — daher wird er durch den eigenen Befehl ersetzt, statt parallel dazu zu laufen (was zu Konflikten zwischen Pull und Push im selben Lauf führen könnte).

Das Skript stellt nur die topgrade-Konfiguration in das chezmoi-Quellverzeichnis bereit; es führt keine Commits oder Pushes durch — diese werden später durch topgrade via den `"Chezmoi Push"`-Befehl durchgeführt.

## Quellen

- [topgrade](https://github.com/topgrade-rs/topgrade) — das Werkzeug, das dieses Skript installiert und konfiguriert.
- [lilays Fedora/RHEL COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) — die Paketquelle für klassische Fedora/RHEL-Systeme und optionale COPR/rpm-ostree-Atomic-Installationen.
- [Universal Blue / ublue-os](https://universal-blue.org/) — die theme-update-Befehle, die auf Bazzite und anderen ublue-os-Images über `[include]` eingebunden werden.
- [chezmoi](https://www.chezmoi.io/) — der Dotfiles-Manager, an den dieses Skript die generierte Konfiguration optional übergeben kann.

## Lizenz

[MIT](LICENSE)
