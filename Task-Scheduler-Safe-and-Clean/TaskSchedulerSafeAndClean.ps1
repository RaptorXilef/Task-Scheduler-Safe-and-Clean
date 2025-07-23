<#
.SYNOPSIS
    Tool zum Sichern und Löschen von geplanten Aufgaben in der Windows Aufgabenplanung.

.DESCRIPTION
    Dieses PowerShell-Skript ermöglicht das einfache Sichern (Exportieren) und anschließende Löschen
    einer spezifischen geplanten Aufgabe in der Windows Aufgabenplanung. Es fragt den Benutzer nach
    dem Namen und dem Pfad der Aufgabe.

    Das Besondere an diesem Skript ist seine Robustheit:
    1.  Es versucht zunächst, die Aufgabe mit den standardmäßigen PowerShell-Cmdlets
        (Get-ScheduledTask, Export-ScheduledTask, Unregister-ScheduledTask) zu bearbeiten.
    2.  Sollte der Zugriff über die PowerShell-Cmdlets fehlschlagen (z.B. weil die Aufgabe
        beschädigt ist oder in einem inkonsistenten Zustand vorliegt), schaltet das Skript
        automatisch auf einen Fallback-Mechanismus um.
    3.  Der Fallback nutzt das native Windows-Kommandozeilen-Tool "schtasks.exe", welches oft
        auch mit Aufgaben umgehen kann, die für PowerShell-Cmdlets nicht zugänglich sind.
        Es wird versucht, die Aufgabe per "schtasks /query /xml" zu sichern und anschließend
        per "schtasks /delete" zu löschen.

    Eine wichtige Ergänzung ist die Prüfung der Backup-Datei: Nach dem Export wird überprüft,
    ob die erzeugte XML-Datei leer ist. Ist sie leer, wird der Benutzer gefragt, ob die Aufgabe
    dennoch gelöscht werden soll, da ein vollständiges Backup nicht erstellt werden konnte.

    Alle Backups werden zentral in einem Ordner namens 'Backups' abgelegt, der sich im selben
    Verzeichnis wie das Skript befindet. Innerhalb dieses 'Backups'-Ordners wird die ursprüngliche
    Ordnerstruktur der Aufgabenplanung beibehalten.

    Nach jedem Durchlauf fragt das Skript, ob eine weitere Aufgabe bearbeitet werden soll,
    was eine Stapelverarbeitung mehrerer Aufgaben ermöglicht. Der Bildschirm wird dabei vor jedem
    neuen Durchgang geleert, um die Übersichtlichkeit zu verbessern.

.NOTES
    Autor: Felix Maywald
    Version: 0.0.1.7 (Behebung von $true/$false-Zuweisungsfehlern)
    Datum: 23. Juli 2025

.EXAMPLE
    Um das Skript auszuführen, navigiere in einer Administrator-PowerShell-Konsole
    (oder einer Administrator-CMD-Konsole mit 'chcp 65001' am Anfang) in das Verzeichnis des Skripts
    und führe es mit '.\DeinSkriptName.ps1' aus.

    Beispiel-Eingaben während der Ausführung:
    - Aufgabenname: 'MeineAufgabe' (für eine Aufgabe im Hauptverzeichnis der Aufgabenplanung)
    - Aufgabenpfad: LEER lassen (für das Hauptverzeichnis)
      --> Backup wird gespeichert unter: Skriptverzeichnis\Backups\MeineAufgabe.xml

    - Aufgabenname: 'Startup' (für eine Aufgabe im Unterordner)
    - Aufgabenpfad: 'PCMeter' (für einen Ordner namens 'PCMeter')
      --> Backup wird gespeichert unter: Skriptverzeichnis\Backups\PCMeter\Startup.xml

.PREREQUISITES
    - Windows PowerShell 5.1 oder höher (oder PowerShell Core 7.x).
    - Ausführung als Administrator ist zwingend erforderlich!
    - Bei Start aus einer CMD-Datei oder -Konsole, die Umlaute enthält, muss 'chcp 65001' am Anfang stehen.
    - Pfade und Dateinamen sollten möglichst keine Umlaute oder Sonderzeichen enthalten,
      um Kodierungsprobleme zu vermeiden, auch wenn 'chcp 65001' hilft.
#>

# --- START DES SKRIPTS ---

# Die do-while-Schleife ermöglicht es dem Benutzer, mehrere Aufgaben hintereinander zu bearbeiten.
do {
    # Bildschirm am Anfang jeder Schleifen-Iteration leeren, für eine saubere Anzeige.
    Clear-Host

    # Löschen der Variablen aus dem vorherigen Durchlauf, um saubere Bedingungen zu gewährleisten
    Remove-Variable TaskName, TaskPathRaw, TaskPath, FullTaskPathName, ExportFolderPath, ExportPath, taskExists, taskSuccessfullyProcessed, useSchtasksFallback, currentTaskBackupSuccessful, currentTaskDeletionSuccessful, shouldProceedWithDeletion -ErrorAction SilentlyContinue

    # Benutzer nach dem genauen Namen der zu bearbeitenden Aufgabe fragen
    $TaskName = Read-Host "Bitte geben Sie den genauen Namen der Aufgabe ein (z.B. 'MeineAufgabe' oder 'StartDeffekteAufgabe')"

    # Benutzer nach dem Pfad der Aufgabe fragen.
    # Der Pfad wird als Raw-Eingabe gelesen und dann normalisiert.
    $TaskPathRaw = Read-Host "Bitte geben Sie den Pfad der Aufgabe ein (z.B. 'test' für Ordner 'test', 'test\sub' für Unterordner oder LEER '' für das Hauptverzeichnis)"

    # --- PFADNORMALISIERUNG ---
    # Passt die Benutzereingabe an das von PowerShell und schtasks benötigte Format an.
    if ([string]::IsNullOrWhiteSpace($TaskPathRaw)) {
        # Wenn die Eingabe leer ist, ist es das Hauptverzeichnis der Aufgabenplanung.
        $TaskPath = '\'
        # Für den Exportpfad brauchen wir hier keinen Unterordner relativ zum Skript.
        $RelativeExportFolder = '' 
    } else {
        # Stellt sicher, dass der Pfad mit einem Backslash beginnt und entfernt eventuelle doppelte oder abschließende Backslashes.
        $TaskPath = '\' + $TaskPathRaw.TrimStart('\').TrimEnd('\')
        # Für den Exportpfad entfernen wir den führenden Backslash, da $PSScriptRoot bereits der "Anker" ist.
        $RelativeExportFolder = $TaskPathRaw.TrimStart('\').TrimEnd('\')
    }

    # Erstellt den vollständigen Pfadnamen der Aufgabe, wie er von schtasks.exe benötigt wird.
    $FullTaskPathName = Join-Path -Path $TaskPath -ChildPath $TaskName

    # --- ANPASSUNG DES EXPORTPFADES UND ERSTELLUNG DER ORDNERSTRUKTUR ---
    # Definiert den vollständigen Pfad des Ordners, in dem die Sicherungsdatei abgelegt werden soll.
    # Dies kombiniert den Skriptpfad mit dem expliziten 'Backups'-Ordner und der relativen Ordnerstruktur aus der Aufgabenplanung.
    # Korrektur des Join-Path Fehlers: Verkettung der Aufrufe, da ChildPath kein Array direkt nimmt in allen PS-Versionen.
    $ExportFolderPath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Backups') -ChildPath $RelativeExportFolder

    # Stellt sicher, dass der Zielordner für das Backup existiert.
    New-Item -ItemType Directory -Path $ExportFolderPath -Force | Out-Null 

    # Definiert den vollständigen Pfad und Dateinamen für die Sicherungsdatei (XML).
    $ExportPath = Join-Path -Path $ExportFolderPath -ChildPath "$TaskName.xml"

    Write-Host "`nÜberprüfe, ob die Aufgabe '$TaskName' im Pfad '$TaskPath' existiert..."

    # Initialisierung von Statusvariablen für den aktuellen Durchlauf.
    $taskSuccessfullyProcessed = $false
    $useSchtasksFallback = $false
    $currentTaskBackupSuccessful = $false
    $shouldProceedWithDeletion = $false

    # --- ERSTER VERSUCH: BEARBEITUNG DER AUFGABE MIT POWERSHELL-CMDLETS ---
    try {
        $taskExists = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
        Write-Host "Aufgabe '$TaskName' im Pfad '$TaskPath' mit Get-ScheduledTask gefunden."

        Write-Host "Versuche, die Aufgabe zu sichern nach '$ExportPath' (PowerShell-Methode)..."
        try {
            $taskToExportPs = $taskExists
            $taskToExportPs.Xml -replace "`n", "`r`n" | Out-File -FilePath $ExportPath -Encoding UTF8 -Force
            
            if (Test-Path $ExportPath) {
                $fileContent = Get-Content -Path $ExportPath -Raw
                if (-not ([string]::IsNullOrWhiteSpace($fileContent)) -and $fileContent.Length -gt 5) {
                    $currentTaskBackupSuccessful = $true
                }
            }
        }
        catch {
            Write-Warning "Fehler beim Exportieren der Aufgabe '$TaskName' (PowerShell-Methode): $($_.Exception.Message)"
        }

        # --- ENTSCHEIDUNG ÜBER LÖSCHUNG NACH BACKUP-VERSUCH (PowerShell-Methode) ---
        if ($currentTaskBackupSuccessful) {
            Write-Host "Backup '$ExportPath' wurde erfolgreich erstellt und ist gültig."
            $shouldProceedWithDeletion = $true
        } else {
            Write-Warning "WARNUNG: Die Backup-Datei '$ExportPath' ist leer, fehlerhaft oder konnte nicht erstellt werden."
            $confirmDelete = Read-Host "Möchten Sie die Aufgabe '$TaskName' trotzdem löschen, obwohl das Backup fehlgeschlagen ist? (J/N)"
            if ($confirmDelete -eq 'j' -or $confirmDelete -eq 'J') {
                $shouldProceedWithDeletion = $true
                Write-Host "Der Benutzer hat die Löschung trotz fehlendem Backup bestätigt."
            } else {
                Write-Host "Löschen der Aufgabe wurde vom Benutzer abgebrochen."
            }
        }

        # Wenn das Löschen erlaubt ist, führe es aus.
        if ($shouldProceedWithDeletion) {
            Write-Host "Versuche, die Aufgabe '$TaskName' aus Pfad '$TaskPath' zu löschen (PowerShell-Methode)..."
            try {
                Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction Stop
                Write-Host "Aufgabe '$TaskName' erfolgreich gelöscht (PowerShell-Methode)."
                $taskSuccessfullyProcessed = $true
            }
            catch {
                Write-Warning "Fehler beim Löschen der Aufgabe '$TaskName' (PowerShell-Methode): $($_.Exception.Message)"
                $taskSuccessfullyProcessed = $false
            }
        }
    }
    catch {
        Write-Warning "Fehler: Die Aufgabe '$TaskName' im Pfad '$TaskPath' wurde von Get-ScheduledTask nicht gefunden oder ist nicht zugänglich."
        Write-Host "Versuche Fallback mit schtasks.exe..."
        $useSchtasksFallback = $true
    }

    # --- FALLBACK: BEARBEITUNG DER AUFGABE MIT SCHTASKS.EXE ---
    if ($useSchtasksFallback) {
        Write-Host "Versuche, die Aufgabe mit schtasks.exe zu finden und zu bearbeiten..."
        
        $schtasksQuery = schtasks /query /tn "$FullTaskPathName" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Fehler: Die Aufgabe '$FullTaskPathName' wurde auch von schtasks.exe nicht gefunden."
            Write-Host "Bitte stellen Sie sicher, dass der Aufgabenname und der Pfad korrekt sind und die Aufgabe nicht beschädigt ist."
            $taskSuccessfullyProcessed = $false
        } else {
            Write-Host "Aufgabe '$FullTaskPathName' mit schtasks.exe gefunden."
            
            Write-Host "Versuche, die Aufgabe zu sichern nach '$ExportPath' (schtasks.exe-Methode)..."
            schtasks /query /tn "$FullTaskPathName" /xml > "$ExportPath" 2>&1
            
            if (Test-Path $ExportPath) {
                $fileContent = Get-Content -Path $ExportPath -Raw
                if (-not ([string]::IsNullOrWhiteSpace($fileContent)) -and $fileContent.Length -gt 5) {
                    $currentTaskBackupSuccessful = $true
                }
            }

            # --- ENTSCHEIDUNG ÜBER LÖSCHUNG NACH BACKUP-VERSUCH (schtasks.exe-Methode) ---
            if ($currentTaskBackupSuccessful) {
                Write-Host "Backup '$ExportPath' wurde erfolgreich erstellt und ist gültig."
                $shouldProceedWithDeletion = $true
            } else {
                Write-Warning "WARNUNG: Die Backup-Datei '$ExportPath' ist leer, fehlerhaft oder konnte nicht erstellt werden."
                $confirmDelete = Read-Host "Möchten Sie die Aufgabe '$TaskName' trotzdem löschen, obwohl das Backup fehlgeschlagen ist? (J/N)"
                if ($confirmDelete -eq 'j' -or $confirmDelete -eq 'J') {
                    $shouldProceedWithDeletion = $true
                    Write-Host "Der Benutzer hat die Löschung trotz fehlendem Backup bestätigt."
                } else {
                    Write-Host "Löschen der Aufgabe wurde vom Benutzer abgebrochen."
                }
            }

            # Wenn das Löschen erlaubt ist, führe es aus.
            if ($shouldProceedWithDeletion) {
                Write-Host "Versuche, die Aufgabe '$FullTaskPathName' zu löschen (schtasks.exe-Methode)..."
                schtasks /delete /tn "$FullTaskPathName" /f 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Aufgabe '$FullTaskPathName' erfolgreich gelöscht (schtasks.exe-Methode)."
                    $taskSuccessfullyProcessed = $true
                } else {
                    Write-Warning "Fehler beim Löschen der Aufgabe '$FullTaskPathName' (schtasks.exe-Methode): $($LASTEXITCODE)"
                    $taskSuccessfullyProcessed = $false
                }
            }
        }
    }

    # --- ABSCHLUSSMELDUNGEN FÜR DEN AKTUELLEN DURCHLAUF ---
    if ($taskSuccessfullyProcessed) {
        Write-Host "Aufgabe '$TaskName' wurde vollständig bearbeitet (gesichert und gelöscht)."
    } else {
        Write-Warning "Die Bearbeitung der Aufgabe '$TaskName' konnte nicht abgeschlossen werden."
        Write-Host "Grund: Das Backup fehlte/war ungültig und/oder die Löschung wurde abgebrochen/fehlgeschlagen."
    }

    $continue = Read-Host "`nMöchten Sie eine weitere Aufgabe bearbeiten? (J/N)"
    Write-Host ""

} while ($continue -eq 'j' -or $continue -eq 'J')

# --- ENDE DES SKRIPTS ---
Write-Host "Skript beendet."
pause
