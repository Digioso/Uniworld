# Uniworld Character Manager
Ein Character-Manager/Generator für das Pen & Paper System Uniworld.

# Windows Download
<br>
Für Windows gibt es eine ausführbare Datei bei den Releases: https://github.com/Digioso/Uniworld/releases/latest<br>
Bitte die Bilder aus dem Release ebenfalls herunterladen und im gleichen Verzeichnis platzieren.<br>

# Installation

Falls du das Skript lieber direkt ausführen möchtest:<br>
Lade den Quellcode und die Bilder von Github herunter und platziere sie in einem Verzeichnis deiner Wahl.<br>
Z.B. das Repository als zip herunterladen oder mit: git clone https://github.com/Digioso/Uniworld.git<br><br>

Windows:
Lade dir StrawberryPerl von https://www.strawberryperl.com herunter. Bitte installiere es nach C:\strawberry<br>
Ich habe die Erfahrung gemacht, dass andere Installationspfade ggf. zu Problemen führen.<br>
Öffne eine Administrator Eingabeaufforderung.<br>
Führe dann die folgenden Befehle aus:<br>
cpan CPAN (hier kann es sein, dass du ein paar Sachen beim ersten Start bestätigen muss. Z.B. falls du einen Proxy verwendest. Im Normalfall alles auf Default lassen).<br>
cpan PDF::API2<br>
cpan Browser::Open<br>
set LC_ALL=C<br>
set LANG=C<br>
cpanm https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/patched_cpan_modules/Tk-804.036_001.tar.gz<br>
cpan Tk::Balloon<br><br>

Ubuntu Linux:<br>
Führe die folgenden Befehle in einem Terminal aus:<br>
cd verzeichnis-mit-den-dateien<br>
chmod +x ucm.pl<br>
sudo apt update<br>
sudo apt -y install perl perl-tk libbrowser-open-perl<br>
sudo cpan CPAN (hier kann es sein, dass du ein paar Sachen beim ersten Start bestätigen muss. Z.B. falls du einen Proxy verwendest. Im Normalfall alles auf Default lassen).<br>
sudo cpan PDF::API2<br>
sudo cpan Tk::Balloon<br>
Anschließend kann die ucm.pl Datei ausgeführt werden. Z.B. über den Dateibrowser mit einem Rechtsklick und dann 'Run as Program'.<br><br>

Andere Linux-Distributionen:<br>
Führe die folgenden Befehle in einem Terminal aus:<br>
cd verzeichnis-mit-den-dateien<br>
chmod +x ucm.pl<br>
sudo cpan CPAN (hier kann es sein, dass du ein paar Sachen beim ersten Start bestätigen muss. Z.B. falls du einen Proxy verwendest. Im Normalfall alles auf Default lassen).<br>
sudo cpan PDF::API2<br>
sudo cpan Browser::Open<br>
export LC_ALL=C<br>
export LANG=C<br>
sudo cpan Tk<br>
sudo cpan Tk::Balloon<br>
Anschließend kann die ucm.pl Datei ausgeführt werden. Z.B. über den Dateibrowser mit einem Rechtsklick und dann 'Run as Program'.<br><br>

Dieses Tool wurde mit Hilfe von KI erstellt.<br>
Genutzte KI:<br>
ChatGPT<br>
Deepseek<br>
Google Gemini<br>
Mistral Le Chat<br>
Perplexity<br>

Dieses Produkt bezieht sich auf das Regelsystem Savage Worlds, erhältlich bei der Pinnacle Entertainment Group unter www.peginc.com. Savage Worlds und alle zugehörigen Logos und Warenzeichen sind urheberrechtlich geschützt durch die Pinnacle Entertainment Group. Verwendung mit Genehmigung. Die deutsche Übersetzung der Begrifflichkeiten von Ulisses Spiele darf verwendet werden. Pinnacle oder Ulisses Spiele geben keine Zusicherungen oder Garantien in Bezug auf die Qualität, Funktionsfähigkeit oder Eignung dieses Produkts für einen bestimmten Zweck.
![Savage-Worlds-Fanprodukt-Logo](https://github.com/Digioso/Uniworld/blob/main/Savage-Worlds-Fanprodukt-Logo.png?raw=true)

This game references the Savage Worlds game system, available from Pinnacle Entertainment Group at www.peginc.com. It is unofficial Media Content permitted under the Media Network Content Agreement. This content is not managed, approved, or endorsed by Pinnacle Entertainment Group. Certain portions of the materials used are the intellectual property of Pinnacle, and all rights are reserved. Savage Worlds, all related settings, and unique characters, locations, and characters, logos and trademarks are copyrights of Pinnacle Entertainment Group.
![Savage-Worlds-Media-Network-Logo](https://github.com/Digioso/Uniworld/blob/main/SW_LOGO_MN_2019.png?raw=true)
