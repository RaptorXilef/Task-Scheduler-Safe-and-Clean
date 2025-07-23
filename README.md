# Task-Scheduler-Safe-and-Clean
Task Scheduler Safe and Clean` ermöglicht das **Sichern (Exportieren)** und anschließende **Löschen** spezifischer Aufgaben, selbst wenn diese beschädigt oder für PowerShell-Cmdlets nicht direkt zugänglich sind.


# Task Scheduler Safe and Clean

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?style=flat-square&logo=powershell)](https://learn.microsoft.com/de-de/powershell/scripting/whats-new/what-s-new-in-powershell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 📝 Kurzbeschreibung

`Task Scheduler Safe and Clean` ist ein robustes PowerShell-Skript, das entwickelt wurde, um die Verwaltung von geplanten Aufgaben in der Windows Aufgabenplanung zu vereinfachen. Es ermöglicht das **Sichern (Exportieren)** und anschließende **Löschen** spezifischer Aufgaben, selbst wenn diese beschädigt oder für PowerShell-Cmdlets nicht direkt zugänglich sind.

## ✨ Funktionen

* **Sichere Löschung:** Exportiert Aufgaben in ein zentrales Backup-Verzeichnis, bevor sie gelöscht werden.
* **Robuster Fallback-Mechanismus:** Nutzt standardmäßig PowerShell-Cmdlets (`Get-ScheduledTask`, `Export-ScheduledTask`, `Unregister-ScheduledTask`). Bei Misserfolg wird automatisch auf `schtasks.exe` zurückgegriffen, um auch beschädigte oder inkonsistente Aufgaben zu handhaben.
* **Backup-Integritätsprüfung:** Überprüft, ob die erzeugte XML-Backup-Datei nicht leer ist. Der Benutzer wird gefragt, ob er fortfahren möchte, falls das Backup unvollständig ist.
* **Strukturierte Backups:** Alle Sicherungsdateien werden im Ordner `Backups` innerhalb des Skriptverzeichnisses abgelegt, wobei die ursprüngliche Ordnerstruktur der Aufgabenplanung beibehalten wird.
* **Interaktive Bedienung:** Fragt den Benutzer nach dem Aufgabennamen und -pfad.
* **Stapelverarbeitung:** Ermöglicht die Bearbeitung mehrerer Aufgaben hintereinander in einer einzigen Skript-Sitzung.

## 🚀 Voraussetzungen

* **Betriebssystem:** Windows 7 oder neuer (getestet auf Windows 10/11).
* **PowerShell:** Windows PowerShell 5.1 oder höher (oder PowerShell Core 7.x).
* **Administratorrechte:** Das Skript muss **zwingend als Administrator ausgeführt** werden, um Aufgaben sichern und löschen zu können.
* **Codepage (optional):** Bei der Ausführung aus einer CMD-Konsole, die Umlaute enthält, kann `chcp 65001` vor dem Start des Skripts erforderlich sein.

## 🖥️ Verwendung

1.  **Herunterladen:** Lade die Skriptdateien `TaskSchedulerSafeAndClean.ps1` und TSSAC-start(Admin).cmd in ein Verzeichnis deiner Wahl herunter.
2.  **CMD als Administrator öffnen:**
    * Rechtsklicke auf "TSSAC-start(Admin).cmd" und wähle "Als Administrator ausführen".
3.  **Anweisungen folgen:** Das Skript wird dich interaktiv nach dem Namen und optional dem Pfad der zu bearbeitenden Aufgabe fragen.

## 🖥️ Verwendung (alternativ)

1.  **Herunterladen:** Lade die Skriptdatei `TaskSchedulerSafeAndClean.ps1` in ein Verzeichnis deiner Wahl herunter.
2.  **Administrator-PowerShell öffnen:**
    * Suche nach "PowerShell" im Startmenü.
    * Rechtsklicke auf "Windows PowerShell" und wähle "Als Administrator ausführen".
3.  **Zum Skript-Verzeichnis navigieren:**
    ```powershell
    cd "C:\Pfad\zu\deinem\Skriptordner"
    ```
    (Ersetze `"C:\Pfad\zu\deinem\Skriptordner"` durch den tatsächlichen Pfad.)
4.  **Skript ausführen:**
    ```powershell
    .\TaskSchedulerSafeAndClean.ps1
    ```
5.  **Anweisungen folgen:** Das Skript wird dich interaktiv nach dem Namen und optional dem Pfad der zu bearbeitenden Aufgabe fragen.

### Beispiel-Interaktion:

```powershell
Bitte geben Sie den genauen Namen der Aufgabe ein (z.B. 'MeineAufgabe' oder 'StartDeffekteAufgabe'): MeineAufgabe
Bitte geben Sie den Pfad der Aufgabe ein (z.B. 'test' für Ordner 'test', 'test\sub' für Unterordner oder LEER für das Hauptverzeichnis):

Überprüfe, ob die Aufgabe 'MeineAufgabe' im Pfad '\' existiert...
Aufgabe 'MeineAufgabe' im Pfad '\' mit Get-ScheduledTask gefunden.
Versuche, die Aufgabe zu sichern nach 'R:\_Aufgabenplanung\Backups\MeineAufgabe.xml' (PowerShell-Methode)...
Backup 'R:\_Aufgabenplanung\Backups\MeineAufgabe.xml' wurde erfolgreich erstellt und ist gültig.
Versuche, die Aufgabe 'MeineAufgabe' aus Pfad '\' zu löschen (PowerShell-Methode)...
Aufgabe 'MeineAufgabe' erfolgreich gelöscht (PowerShell-Methode).
Aufgabe 'MeineAufgabe' wurde vollständig bearbeitet (gesichert und gelöscht).

Möchten Sie eine weitere Aufgabe bearbeiten? (J/N): N
Skript beendet.
