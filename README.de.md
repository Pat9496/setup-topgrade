# setup-topgrade

Ein Bash-Skript, das [topgrade](https://github.com/topgrade-rs/topgrade) installiert und konfiguriert — das Werkzeug, das alle Aktualisierungsbefehle des Systems (apt/dnf/flatpak/cargo/firmware/etc.) in einem Schritt ausführt — auf jedem Linux-System, einschließlich OSTree-basierter atomarer und unveränderlicher Systeme wie Bazzite und Fedora Silverblue/Kinoite/Atomic sowie bootc-basierten atomaren Hosts.

## Features

- **Funktioniert auf verschiedenen Distributionen.** Verwendet die dokumentierte Installationsmethode für topgrade jeder Distribution, sofern vorhanden (Fedora/RHEL über COPR, Alpine über `apk`, Void über `xbps-install`, Homebrew/Linuxbrew), und lädt ansonsten die vorkompilierte Binärdatei von GitHub Releases in `~/.local/bin` herunter.
- **Behandelt atomare/unveränderliche Systeme korrekt.** Auf rpm-ostree-Hosts (Bazzite, Fedora Silverblue/Kinoite/Atomic) wird die `lilay/topgrade`-COPR-Repo-Datei direkt heruntergeladen und das Paket mit `rpm-ostree install` überlagert — kein `dnf`-Binary erforderlich — und das System wird nicht ohne Rückfrage neu gestartet. Auf atomaren Hosts ohne `rpm-ostree` (nur bootc, oder wenn die COPR-/rpm-ostree-Überlagerung fehlschlägt) wird stattdessen die Binärdatei von GitHub Releases heruntergeladen.
- **Idempotent.** Kann sicher erneut ausgeführt werden. Bereits installiert? Das Skript springt direkt zur Konfiguration und Überprüfung. Bereits konfiguriert? Bestehende Konfigurationen werden nicht überschrieben.
- **Wird mit einer sinnvollen Standardkonfiguration ausgeliefert**, wobei einige Teile (siehe [Konfiguration](#konfiguration)) nur hinzugefügt werden, wenn sie für das System tatsächlich relevant sind.
- **Optionale [chezmoi](https://www.chezmoi.io/)-Integration.** Ist chezmoi installiert und initialisiert, wird die generierte Konfiguration automatisch unter chezmoi-Verwaltung gestellt.
- **Keine unerwarteten Überraschungen.** Dieses Skript soll interaktiv von einer Person ausgeführt werden. Das System wird nicht neu gestartet und bestehende Konfigurationen werden nicht überschrieben, ohne dass eine Bestätigung erfolgt.

## Anforderungen

- Bash
- `curl` oder `wget`
- `sudo`, falls nicht bereits als root läuft und ein privilegierter Installationsschritt erforderlich ist

## Verwendung

```bash
./install-topgrade.sh
```

Das Skript kann jederzeit erneut ausgeführt werden — es erkennt, was bereits abgeschlossen wurde, und setzt an der entsprechenden Stelle fort. Dies ist auf rpm-ostree-Atomic-Hosts zu erwarten: Bei einer neuen Installation wird das Paket über `rpm-ostree` bereitgestellt, was einen Reboot benötigt, um aktiv zu werden, und das Skript wird nicht ohne Rückfrage neu gestartet. Wird diese Rückfrage abgelehnt (oder läuft das Skript in einer nicht-interaktiven Shell, in der es gar nicht fragt), kann der Reboot manuell durchgeführt und das Skript anschließend erneut ausgeführt werden, um die Installation abzuschließen. Auf reinen bootc-Atomic-Hosts ohne `rpm-ostree` wird topgrade als Binärdatei von GitHub Releases installiert, daher ist kein Reboot erforderlich.

## Funktionsweise

topgrade wird in den offiziellen Repositories von Fedora, RHEL oder AlmaLinux nicht paketiert. Auf diesen Distributionen (und auf rpm-ostree/atomaren Hosts, die davon abgeleitet sind) installiert dieses Skript topgrade aus [lilays `lilay/topgrade` COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) — die dokumentierte Methode, um es über `dnf` oder `rpm-ostree` zu erhalten.

Das Skript wählt seine Installationsstrategie basierend auf dem erkannten System:

| System | Strategie |
|---|---|
| Bazzite, Fedora Silverblue/Kinoite/Atomic (rpm-ostree vorhanden) | Lädt die `lilay/topgrade`-COPR-Repo-Datei direkt herunter (kein `dnf` erforderlich) und überlagert das Paket mit `rpm-ostree install`, fragt vor dem Reboot nach |
| Atomarer Host ohne `rpm-ostree` (nur bootc), oder wenn die COPR-/rpm-ostree-Überlagerung fehlschlägt | Lädt die neueste Release-Binärdatei von GitHub in `~/.local/bin/topgrade` herunter |
| Fedora / RHEL / AlmaLinux (nicht-atomar) | Aktiviert das `lilay/topgrade`-COPR, installiert mit `dnf install` |
| Alpine | `apk add topgrade` |
| Void Linux | `xbps-install -Sy topgrade` |
| Homebrew / Linuxbrew vorhanden | `brew install topgrade` |
| Sonstige Systeme (Debian, Ubuntu, Arch, openSUSE oder falls eine native Methode fehlschlägt) | Lädt die neueste Release-Binärdatei von GitHub in `~/.local/bin/topgrade` herunter |

Privilegierte Schritte werden unter `sudo` ausgeführt. Läuft das Skript bereits als root, wird `sudo` übersprungen — dann ist das `sudo`-Binary nicht erforderlich.

## Konfiguration

topgrade liest seine Konfiguration aus `${XDG_CONFIG_HOME:-~/.config}/topgrade.toml`. Existiert diese Datei noch nicht, erstellt das Skript eine. **Bestehende Konfigurationen werden niemals angetastet oder überschrieben.**

Die generierte Konfiguration enthält einige Teile bedingt, basierend darauf, was tatsächlich auf dem System vorhanden ist:

| Konfigurationsteil | Enthalten wenn |
|---|---|
| `[include] paths = ["/etc/ublue-os/topgrade.toml"]` | `/etc/ublue-os/topgrade.toml` existiert (ublue-os/Bazzite theme-update-Befehle) — da `~/.config/topgrade.toml` in `toolbx`/`distrobox`-Container eingebunden wird, kann dies dort einen harmlosen `Unable to read /etc/ublue-os/topgrade.toml`-Fehler protokollieren; das Skript gibt einen Hinweis aus, wenn es die Zeile hinzufügt |
| `[linux] rpm_ostree = true` | Wird auf einem atomaren Host ausgeführt, auf dem `rpm-ostree` verfügbar ist (hat Vorrang vor `bootc`) |
| `[linux] bootc = true` | Wird auf einem atomaren Host ausgeführt, auf dem `rpm-ostree` nicht verfügbar ist, aber `bootc` (reiner bootc-Host ohne anderen unterstützten Paketmanager) |
| `[misc] no_self_update = true` | topgrade wurde tatsächlich über einen Paketmanager installiert (COPR+`rpm-ostree install`, `dnf`, `apk`, `xbps-install` oder Homebrew) — nicht allein deshalb, weil es sich um einen atomaren Host handelt. Reine bootc-Hosts ohne `rpm-ostree` erhalten die Binärdatei von GitHub Releases und erhalten daher **kein** `no_self_update = true` |
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
- [lilays Fedora/RHEL COPR](https://copr.fedorainfracloud.org/coprs/lilay/topgrade/) — die Paketquelle, die auf Fedora, RHEL, AlmaLinux und rpm-ostree/atomaren Hosts verwendet wird.
- [Universal Blue / ublue-os](https://universal-blue.org/) — die theme-update-Befehle, die auf Bazzite und anderen ublue-os-Images über `[include]` eingebunden werden.
- [chezmoi](https://www.chezmoi.io/) — der Dotfiles-Manager, an den dieses Skript die generierte Konfiguration optional übergeben kann.

## Lizenz

[MIT](LICENSE)
