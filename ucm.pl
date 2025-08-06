#!/usr/bin/perl -w
use strict;
use warnings;
use utf8;
use POSIX qw(setlocale LC_ALL ceil);
use POSIX;
use Tk;
use Tk::Scrollbar;
use Tk::Pane;
use Tk::Frame;
use Tk::DialogBox;
use Tk::Canvas;
use Tk::Dialog;
use Tk::Balloon;
use Text::Wrap;
use JSON;
use PDF::API2;
use List::Util qw(sum);
use File::Basename;
use Browser::Open;
use Data::Dumper;
use feature ('say', 'signatures');
no warnings 'experimental::signatures';

# Global variables
setlocale(LC_ALL, 'en_US.UTF-8');
my $characters = {};
my $current_character;
my $next_id = 1; # Character IDs

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

# Attribute und Fertigkeiten
my @char_attributes = ("Charisma", "Körperliche Verfassung", "Reaktion", "Verstand", "Willenskraft");
my @char_skills = (
    "Athletik", "Ausweichen", "Einschüchtern", "Fahren", "Hacken", "Heimlichkeit",
    "Hardware", "Kämpfen", "Nachforschung", "Software", "Überreden", "Überleben",
    "Umhören", "Wahrnehmung"
);

my %char_skill_attributes = (
    "Athletik"       => "Körperliche Verfassung",
    "Ausweichen"     => "Reaktion",
    "Einschüchtern"  => "Willenskraft",
    "Fahren"         => "Reaktion",
    "Hacken"         => "Verstand",
    "Heimlichkeit"   => "Reaktion",
    "Hardware"       => "Verstand",
    "Kämpfen"        => "Reaktion",
    "Nachforschung"  => "Willenskraft",
    "Software"       => "Verstand",
    "Überreden"      => "Charisma",
    "Überleben"      => "Körperliche Verfassung",
    "Umhören"        => "Charisma",
    "Wahrnehmung"    => "Reaktion",
    "Wissen"         => "Verstand"
);

my @avatar_skills = (
    "Athletik", "Craften", "Diebstahl", "Fahrzeug lenken", "Fernkampf", "Heimlichkeit",
    "Heilen", "Inspirieren/Buffen", "Konstitution", "Machtnutzung", "Nahkampf",
    "Provozieren/Taunt", "Überreden", "Wahrnehmung", "Zeugs sammeln"
);
my @avatar_skills_light = (
    "Craften", "Fernkampf","Heilen", "Konstitution", "Körperliches", "Machtnutzung", "Nahkampf",
    "Soziales", "Überreden", "Wahrnehmung", "Zeugs sammeln"
);

# Create main window
my $mw = MainWindow->new;
$mw->title("Uniworld Charakter-Manager");
$mw->geometry("550x250");
$mw->protocol('WM_DELETE_WINDOW', sub { exit_program() });
my $scrolled_main_area  = $mw->Scrolled(
        'Frame',
        -scrollbars => 'osoe' # Scrollbars nur rechts/unten bei Bedarf
    )->pack(-fill => 'both', -expand => 1); # Füllt das gesamte Dialogfenster


my $content_container = $scrolled_main_area->Subwidget('scrolled');
	 
my $link_description = '© 2025 Andreas & Manuela Balthasar GbR - www.andreasbalthasar.de';
my $target_url = 'https://www.andreasbalthasar.de';

my @default_font_config_list = $content_container->fontActual('TkDefaultFont');
my %link_font_spec_hash = @default_font_config_list;
$link_font_spec_hash{-underline} = 1;
my $link_font;
eval {
    $link_font = $mw->fontCreate('linkFont', %link_font_spec_hash);
};
if ($@ || !defined $link_font) {
    # Fallback auf einen einfachen unterstrichenen Font
    my $fallback_font_family = $link_font_spec_hash{-family} || 'TkDefaultFont'; # Nimm Familie oder Default
    eval {
        $link_font = $content_container->fontCreate('linkFontFallback', -family => $fallback_font_family, -underline => 1);
    };
    # Wenn auch Fallback fehlschlägt, nimm die Default-Schrift
    unless (defined $link_font) {
        $link_font = 'TkDefaultFont'; # Name der Default-Schrift
    }
}

my $link_label = $content_container->Label(
    -text       => $link_description,
    -foreground => 'blue',
    -font       => $link_font,
    -cursor     => 'hand2'
)->pack(
    -side => 'bottom', # Nimmt den unteren Rand ein
    -fill => 'x',
    -pady => [5, 2]
);

$link_label->bind('<Button-1>', sub {
    my $success = eval { Browser::Open::open_browser($target_url); 1 };
    unless ($success) {
        my $error_msg = $@ || "Unbekannter Fehler";
        $mw->messageBox(-title => "Fehler", -message => "Konnte URL '$target_url' nicht öffnen: $error_msg", -type => 'ok', -icon => 'error');
}});

my $btn_frame = $content_container->Frame()->pack(
    -side => 'right',   # An die rechte Kante des *verbleibenden* Platzes (oberhalb des Links)
    -fill => 'y',       # Füllt vertikal
    -padx => 5,
    -pady => 5
);
# Buttons innerhalb des btn_frame
$btn_frame->Button(-text => 'Neuen Charakter erstellen', -command => \&create_character)->pack(-fill => 'x', -pady=>1);
$btn_frame->Button(-text => 'Charakter bearbeiten', -command => \&edit_character)->pack(-fill => 'x', -pady=>1);
$btn_frame->Button(-text => 'Charakter löschen', -command => \&delete_character)->pack(-fill => 'x', -pady=>1);
$btn_frame->Button(-text => 'Charaktere speichern', -command => \&save_characters)->pack(-fill => 'x', -pady=>1);
$btn_frame->Button(-text => 'Exportieren als PDF', -command => \&export_to_pdf)->pack(-fill => 'x', -pady=>1);
$btn_frame->Button(-text => 'Beenden', -command => \&exit_program)->pack(-fill => 'x', -pady=>1);


# --- Linker Frame für die Liste (Parent: $content_container, PACKED THIRD mit side left) ---
# Dieser Frame füllt den verbleibenden Platz links vom Button-Frame und oberhalb des Links
my $list_frame = $content_container->Frame()->pack(
    -side => 'left',
    -fill => 'both',    # Füllt horizontal UND vertikal
    -expand => 1,       # Erlaubt das Expandieren, um Platz zu füllen
    -padx => 5,
    -pady => 5
);
my $charlist_label = $list_frame->Label(-text => "Charaktere:")->pack(-side => 'top', -anchor => 'w');
# Frame für Listbox (Kind von $list_frame)
my $char_list_frame = $list_frame->Frame()->pack(-side => 'top', -fill => 'both', -expand => 1); # Nimmt restlichen Platz in list_frame ein
my $listbox = $char_list_frame->Scrolled(
    'Listbox',
    -scrollbars => 'se',
)->pack(-side => 'left', -fill => 'both', -expand => 1);
$listbox->Subwidget('listbox')->bind('<Enter>', sub{$listbox->Subwidget('listbox')->focus()});
$listbox->Subwidget('listbox')->bind('<Leave>', sub {$mw->focus();});
$listbox->bind('<<ListboxSelect>>', \&select_character);

# Load characters into listbox
load_characters();
update_character_list();

# Main loop
MainLoop();
exit 0;

sub get_script_dir
{
	my $dir = my $dirname = dirname(__FILE__);
	$dir = (fileparse($0))[1] if($dir eq 'script');
	return $dir;
}

# Funktion zum Erstellen von transparenten Rechtecken für Klickbereiche
sub create_clickable_area{
    my ($coords, $tag, $canvas) = @_;
    my ($x1, $y1, $x2, $y2) = @$coords;
    $canvas->createRectangle($x1, $y1, $x2, $y2,
        -outline => '',
        -fill => '',
        -tags => $tag
    );
}

sub trim_text {
    my ($text) = @_;
    $text =~ s/\s+$//;  # Entfernt alle Leerzeichen am Ende, einschließlich neuer Zeilen
    return $text;
}

# Delete character
sub delete_character {
	
    unless(defined $current_character)
	{
		$mw->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Charakter wählen',
            -message => "Bitte einen Charakter auswählen."
        );
		return;
	}

    # Get the name of the current character
    my $name = $current_character->{name};
    my $id = $current_character->{id};

    my $response = $mw->messageBox(
        -type    => 'YesNo',
        -icon    => 'question',
        -title   => 'Charakter löschen',
        -message => "Möchten Sie den Charakter '$name' wirklich laöschen?"
    );

    if (defined $response && $response eq 'Yes') {
        # Remove the character from the hash
        delete $characters->{$id};

        # Update the character list
        update_character_list();

        # Clear the current character
        $current_character = undef;
    }
}

# Load saved characters from file
sub load_characters {
    my $file = 'characters.json';
    if (-e $file) {
        open my $fh, '<:encoding(UTF-8)', $file or die "Could not open file '$file': $!";
        local $/; # Enable slurp mode
        $characters = decode_json(<$fh>);
        close $fh;

        # Ensure avatars is an array reference for each character
        foreach my $character (values %$characters) {
            $character->{avatars} = [] unless defined $character->{avatars} && ref($character->{avatars}) eq 'ARRAY';
        }

        # Find the highest ID used
        foreach my $character (values %$characters) {
            $next_id = $character->{id} if $character->{id} > $next_id;
        }
    }
}

# Programm beenden und Charaktere speichern
sub exit_program {
    my $response = $mw->messageBox(
        -type    => 'YesNo',
        -icon    => 'question',
        -title   => 'Charaktere Speichern',
        -message => "Sollen die Charaktere vor dem Beenden gespeichert werden?"
    );

    save_characters() if (defined $response && $response eq 'Yes');
    $mw->destroy();
}

# Save characters to file
sub save_characters {
    my $file = 'characters.json';
    open my $fh, '>:encoding(UTF-8)', $file or die "Could not open file '$file': $!";
    print $fh encode_json($characters);
    close $fh;
    $mw->messageBox(
        -type    => 'Ok',
        -icon    => 'info',
        -title   => 'Charaktere gespeichert',
        -message => "Charaktere wurden gespeichert."
    );
}

# Avatar Management Function
sub manage_avatars {
    my ($parent_dialog, $avatars_ref, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods) = @_;

    # Debugging: Ensure $avatars_ref is an array reference
    unless (ref($avatars_ref) eq 'ARRAY') {
        die "Expected an array reference, but got: " . (ref($avatars_ref) || 'SCALAR');
    }

    my $row = 0;

    my $avatar_label = $parent_dialog->Label(-text => "Avatare")->grid(-row => $row, -column => 0, -columnspan => 2, -sticky => 'w');
    $row++;

    my $avatar_frame = $parent_dialog->Frame()->grid(-row => $row, -column => 0, -columnspan => 2);
    my $avatar_listbox = $avatar_frame->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->pack(-side => 'left', -fill => 'both', -expand => 1);
    $avatar_listbox->Subwidget('listbox')->bind('<Enter>', sub{$avatar_listbox->Subwidget('listbox')->focus()});
    $avatar_listbox->Subwidget('listbox')->bind('<Leave>', sub {$parent_dialog->focus();});

    # Populate the Listbox initially
    foreach my $avatar (@$avatars_ref) {
        $avatar_listbox->insert('end', "$avatar->{name} ($avatar->{game})");
    }

    my $avatar_button_frame = $avatar_frame->Frame()->pack(-side => 'right', -fill => 'y');
    $avatar_button_frame->Button(
        -text    => "Avatar hinzufügen",
        -command => sub { add_avatar(
                $parent_dialog, 
                $avatars_ref, 
                $avatar_listbox,
                $char_attributes,
                $char_attr_mods,
                $char_skills,
                $char_skill_mods
            );  }
    )->pack(-side => 'top');

    $avatar_button_frame->Button(
        -text    => "Avatar bearbeiten",
        -command => sub {  edit_avatar(
                $parent_dialog, 
                $avatars_ref, 
                $avatar_listbox,
                $char_attributes,
                $char_attr_mods,
                $char_skills,
                $char_skill_mods
            );  }
    )->pack(-side => 'top');

    $avatar_button_frame->Button(
        -text    => "Avatar löschen",
        -command => sub { delete_avatar($parent_dialog, $avatars_ref, $avatar_listbox) }
    )->pack(-side => 'top');
}

sub add_avatar {
	my ($parent_dialog, $avatars_ref, $avatar_listbox, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods) = @_;
    my $add_avatar = $parent_dialog->Toplevel();
	$add_avatar->geometry("470x150");  # Set window size
	focus_dialog($add_avatar, "Neuer Avatar - Grunddaten", $parent_dialog);
	my $scrolled_area = $add_avatar->Scrolled(
        'Frame',
        -scrollbars => 'osoe' # Scrollbars nur rechts/unten bei Bedarf
    )->pack(-fill => 'both', -expand => 1); # Füllt das gesamte Dialogfenster
	my $pre_dialog = $scrolled_area->Subwidget('scrolled');

    # Variablen für Eingabefelder
    my ($name, $welt, $angriffstyp, $skill_points) = ("", "", "Nahkampf", 13);

    # GUI-Elemente
    $pre_dialog->Label(-text => "Avatarname:")->grid(-row => 0, -column => 0, -sticky => 'w');
    my $name_entry = $pre_dialog->Entry(-textvariable => \$name)->grid(-row => 0, -column => 1);
	
	$pre_dialog->Label(-text => "Welt:")->grid(-row => 1, -column => 0, -sticky => 'w');
    my $welt_entry = $pre_dialog->Entry(-textvariable => \$welt)->grid(-row => 1, -column => 1);

    $pre_dialog->Label(-text => "Fertigkeitspunkte (Standard 13):")->grid(-row => 2, -column => 0, -sticky => 'w');
    my $skill_entry = $pre_dialog->Entry(
        -textvariable => \$skill_points,
        -validate => 'key',
        -validatecommand => sub { $_[0] =~ /^\d+$/ }
    )->grid(-row => 2, -column => 1);
	
	$pre_dialog->Label(-text => "Angriffstyp:")->grid(-row => 3, -column => 0, -sticky => 'w');
	my $radio1 = $pre_dialog->Radiobutton(
    -text     => 'Nahkampf',
    -variable => \$angriffstyp,
    -value    => 'Nahkampf',
	)->grid(-row => 3, -column => 1, -sticky => 'w');

	my $radio2 = $pre_dialog->Radiobutton(
		-text     => 'Fernkampf',
		-variable => \$angriffstyp,
		-value    => 'Fernkampf',
	)->grid(-row => 3, -column => 2, -sticky => 'w');

	my $radio3 = $pre_dialog->Radiobutton(
		-text     => 'Machtnutzung',
		-variable => \$angriffstyp,
		-value    => 'Machtnutzung',
	)->grid(-row => 3, -column => 3, -sticky => 'w');

    # Bestätigungs-Button
    $pre_dialog->Button(
        -text => "Weiter",
        -command => sub {
            # Validierung der Eingaben
            unless ($name && $welt && $skill_points) {
                $pre_dialog->messageBox(-type => 'Ok', -icon => 'error', 
                    -title => 'Fehler', -message => "Bitte alle Felder ausfüllen!");
                return;
            }
			$pre_dialog->messageBox(-type => 'Ok', -icon => 'info',	-title => 'Machtnutzung', -message => "Bei Machtnutzung bitte im nächsten Schritt die\nentsprechende Anzahl der Machtpunkte eintragen und Mächte hinzufügen.") if('Machtnutzung' eq $angriffstyp);
            $add_avatar->destroy();
            # Haupt-Charaktererstellung aufrufen
            main_avatar_creation($parent_dialog, $avatars_ref, $avatar_listbox, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods, $name, $welt, $angriffstyp, $skill_points);
        }
    )->grid(-row => 4, -columnspan => 2);

    # Abbrechen-Button
    $pre_dialog->Button(
        -text => "Abbrechen",
        -command => sub { $add_avatar->destroy }
    )->grid(-row => 5, -columnspan => 2);
}

sub main_avatar_creation {
    my ($parent_dialog, $avatars_ref, $avatar_listbox, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods, $name, $welt, $angriffstyp, $skill_points) = @_;

    my $add_avatar = $parent_dialog->Toplevel();
    focus_dialog($add_avatar, "Avatar hinzufügen", $parent_dialog);
    $add_avatar->geometry("950x800");  # Set window size
	my $scrolled_area = $add_avatar->Scrolled(
        'Frame',
        -scrollbars => 'osoe'
    )->pack(-fill => 'both', -expand => 1);
    my $avatar_dialog = $scrolled_area->Subwidget('scrolled');
    my $spacer = $avatar_dialog->Label(-text => "", -width => 42)->grid(-row => 0, -column => 0);
	my $balloon = $avatar_dialog->Balloon();
    my $row = 0;

    # Avatar Name
    my $name_label = $avatar_dialog->Label(-text => "Avatar-Name")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $name_entry = $avatar_dialog->Entry(-text => $name)->grid(-row => $row, -column => 1, -sticky => 'w');

    # XP
    my $xp_label = $avatar_dialog->Label(-text => "Erfahrungspunkte")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $xp_entry = $avatar_dialog->Label(-text => 0)->grid(-row => $row, -column => 2, -sticky => 'e');
	
	# Fertigkeitspunkte über
	my $skillpunkt_label = $avatar_dialog->Label(-text => "Fertigkeitspunkte über")->grid(-row => $row, -column => 3, -sticky => 'w');
    my $skillpunkt_entry = $avatar_dialog->Label(-text => $skill_points)->grid(-row => $row, -column => 3, -sticky => 'e');
	
    $row++;

    # Game
    my $game_label = $avatar_dialog->Label(-text => "Welt")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $game_entry = $avatar_dialog->Entry(-text => $welt)->grid(-row => $row, -column => 1, -sticky => 'w');

    # Rank
    my $rank_label = $avatar_dialog->Label(-text => "Rang")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $rank_entry = $avatar_dialog->Label(-width => 11, -text => 'Anfänger')->grid(-row => $row, -column => 2, -sticky => 'e');
    
	# Talentpunkte über
	my $talentpunkt_label = $avatar_dialog->Label(-text => "Talentpunkte über")->grid(-row => $row, -column => 3, -sticky => 'w');
    my $talentpunkt_entry;
	if($angriffstyp eq 'Machtnutzung')
	{
		$talentpunkt_entry = $avatar_dialog->Label(-text => 2)->grid(-row => $row, -column => 3, -sticky => 'e');
	}
	else
	{
		$talentpunkt_entry = $avatar_dialog->Label(-text => 4)->grid(-row => $row, -column => 3, -sticky => 'e');
	}
    $row++;

    # Beschreibung
    my $description_label = $avatar_dialog->Label(-text => "Beschreibung")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $description_entry = $avatar_dialog->Entry()->grid(-row => $row, -column => 1, -sticky => 'w');

    # Level
    my $level_label = $avatar_dialog->Label(-text => "Level")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $level_entry = $avatar_dialog->Label(-text => 0)->grid(-row => $row, -column => 2, -sticky => 'e');
    $row++;

    # Gilden
    my $gilden_label = $avatar_dialog->Label(-text => "Gildenzugehörigkeit")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $gilden_entry = $avatar_dialog->Entry()->grid(-row => $row, -column => 1, -sticky => 'w');

    # Bennies
    my $bennies_label = $avatar_dialog->Label(-text => "Bennies")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $bennies_entry = $avatar_dialog->Entry(-width => 2, -textvariable => 3)->grid(-row => $row, -column => 2, -sticky => 'n');
    my $benniesmax_label = $avatar_dialog->Label(-width => 3, -text => "von ")->grid(-row => $row, -column => 2, -sticky => 'e', -ipadx => 35);
    my $benniesmax_entry = $avatar_dialog->Entry(-width => 2, -textvariable => 3)->grid(-row => $row, -column => 2, -sticky => 'e');
	
	# Heiltränke
	my $heiltraenke_label = $avatar_dialog->Label(-text => "Tägliche Heiltränke")->grid(-row => $row, -column => 3, -sticky => 'w');
    my $heiltraenke_entry = $avatar_dialog->Label(-text => 0)->grid(-row => $row, -column => 3, -sticky => 'e');
    $row++;
	
	# Machtpunkte
    my $mp_label = $avatar_dialog->Label(-text => "Machtpunkte")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $mp_entry = $avatar_dialog->Entry()->grid(-row => $row, -column => 1, -sticky => 'w');

    # Wunden
    my $wunden_label = $avatar_dialog->Label(-text => "Wunden")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $wunden_entry = $avatar_dialog->Entry(-width => 2, -textvariable => 0)->grid(-row => $row, -column => 2, -sticky => 'n');
    my $wundenmax_label = $avatar_dialog->Label(-width => 3, -text => "von ")->grid(-row => $row, -column => 2, -sticky => 'e', -ipadx => 35);
    my $wundenmax_entry = $avatar_dialog->Entry(-width => 2, -textvariable => 4)->grid(-row => $row, -column => 2, -sticky => 'e');
	
	# Machttränke
	my $machttraenke_label = $avatar_dialog->Label(-text => "Tägliche Machttränke")->grid(-row => $row, -column => 3, -sticky => 'w');
    my $machttraenke_entry = $avatar_dialog->Label(-text => 0)->grid(-row => $row, -column => 3, -sticky => 'e');
	
	# Parade
	my $parade_basis = $avatar_dialog->Label(-width => 3)->grid(-row => 7, -column => 2, -sticky => 'n');
	my $parademod_entry = $avatar_dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 7, -column => 3, -sticky => 'w');
	my $paradegs_entry = $avatar_dialog->Label(-width => 3)->grid(-row => 7, -column => 3, -sticky => 'e');
	
	
    my $robust_basis = $avatar_dialog->Label(-width => 3)->grid(-row => 8, -column => 2, -sticky => 'n');
    my $robustmod_entry = $avatar_dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 8, -column => 3, -sticky => 'w');
    my $robustgs_entry = $avatar_dialog->Label(-width => 3)->grid(-row => 8, -column => 3, -sticky => 'e');
	
    # Skills
    my $skill_label = $avatar_dialog->Label(-text => "Fertigkeiten")->grid(-row => $row + 1, -column => 0, -columnspan => 2);
    $row+=2;

    # Initialize skill values and modifiers
    my %avatar_skills_values = map { $_ => 0 } @avatar_skills;
    my %skill_mods = map { $_ => 0 } @avatar_skills;
    my %skills_fields;
	$avatar_skills_values{Athletik} = 4;
	$avatar_skills_values{Heimlichkeit} = 4;
	$avatar_skills_values{Konstitution} = 4;
	$avatar_skills_values{Überreden} = 4;
	$avatar_skills_values{Wahrnehmung} = 4;
	if($angriffstyp eq 'Nahkampf')
	{
		$avatar_skills_values{Nahkampf} = 4;
	}
	elsif($angriffstyp eq 'Fernkampf')
	{
		$avatar_skills_values{Fernkampf} = 4;
	}
	else
	{
		$avatar_skills_values{Machtnutzung} = 4;
	}

    foreach my $skill (@avatar_skills) {
        $skills_fields{$skill}{label} = $avatar_dialog->Label(-text => $skill)->grid(-row => $row, -column => 0, -sticky => 'w');
        $skills_fields{$skill}{skillmod_label} = $avatar_dialog->Label(-width => 3, -text => "Mod")->grid(-row => $row, -column => 0, -sticky => 'n');
        $skills_fields{$skill}{skillmod_entry} = $avatar_dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
            my $new_value = shift;
            return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
            return 0;
        })->grid(-row => $row, -column => 0, -sticky => 'e');

        $skills_fields{$skill}{entry} = $avatar_dialog->Label(-text => "W$avatar_skills_values{$skill}")->grid(-row => $row, -column => 1, -sticky => 'w');

        $skills_fields{$skill}{skillmod_entry}->bind('<KeyRelease>', sub {
            my $mod_value = $skills_fields{$skill}{skillmod_entry}->get();
            if ($mod_value =~ /^[\+-]?\d+$/) {
                update_display_avatar($avatar_skills_values{$skill}, $mod_value, $skills_fields{$skill}{entry}, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
                $skill_mods{$skill} = $mod_value;
            }
			if($skill eq "Nahkampf")
			{
				update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
			}
			elsif($skill eq "Konstitution")
			{
				update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
			}
        });

        my $increase_button = $avatar_dialog->Button(
            -text => "+",
            -command => sub {
				if($skillpunkt_entry->cget('-text') == 0)
				{
					$avatar_dialog->messageBox(
					-type    => 'Ok',
					-icon    => 'error',
					-title   => 'Keine Fertigkeitspunkte mehr',
					-message => "Keine Fertigkeitspunkte mehr zum Verteilen!"
					);
				}
				else
				{
					my $current_value = $avatar_skills_values{$skill};
					if ($current_value =~ /^(\d+)$/) {
						my $number = $1;
						if($number == 0) {
							$avatar_skills_values{$skill} = 4;
							$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 1);
						}
						elsif ($number < 12) {
							if($number > 6 && $skillpunkt_entry->cget('-text') < 2)
							{
								$avatar_dialog->messageBox(
								-type    => 'Ok',
								-icon    => 'error',
								-title   => 'Nicht genug Fertigkeitspunkte',
								-message => "Fertigkeiten über W8 kosten 2 Punkte, es ist aber nur noch einer da!"
								);
							}
							else
							{
								$number+=2;
								$avatar_skills_values{$skill} = $number;
								if($number > 8)
								{
									$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 2);
								}
								else
								{
									$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 1);
								}
							}
							
						}
						elsif ($number == 12)
						{
							if($skillpunkt_entry->cget('-text') < 2)
							{
								$avatar_dialog->messageBox(
								-type    => 'Ok',
								-icon    => 'error',
								-title   => 'Nicht genug Fertigkeitspunkte',
								-message => "Fertigkeiten über W8 kosten 2 Punkte, es ist aber nur noch einer da!"
								);
							}
							else
							{
								$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 2);
								$avatar_skills_values{$skill} = "12+1";
							}
						}
					}
					elsif ($current_value =~ /^12\+(\d+)$/)
					{
						my $number = $1;
						if($skillpunkt_entry->cget('-text') < 2)
						{
							$avatar_dialog->messageBox(
							-type    => 'Ok',
							-icon    => 'error',
							-title   => 'Nicht genug Fertigkeitspunkte',
							-message => "Fertigkeiten über W8 kosten 2 Punkte, es ist aber nur noch einer da!"
							);
						}
						else
						{
							$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 2);
							$number++;
							$avatar_skills_values{$skill} = "12+$number";
						}
					}
					update_display_avatar($avatar_skills_values{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
					if($skill eq "Nahkampf")
					{
						update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
					}
					elsif($skill eq "Konstitution")
					{
						update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
					}
				}
            }
        )->grid(-row => $row, -column => 1, -sticky => 'n', -ipadx=> 8);

        my $decrease_button = $avatar_dialog->Button(
            -text => "-",
            -command => sub {
                my $current_value = $avatar_skills_values{$skill};
                if ($current_value =~ /^(\d+)$/) {
                    my $number = $1;
                    if($number == 4) {
						$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 1);
                        $avatar_skills_values{$skill} = 0;
                    }
                    elsif ($number > 0) {
                        $number-=2;
                        $avatar_skills_values{$skill} = $number;
						if($number > 6)
						{
							$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 2);
						}
						else
						{
							$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 1);
						}
                    }
                } elsif ($current_value =~ /^12\+(\d+)$/) {
                    my $number = $1;
					$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 2);
                    if ($number > 1) {
                        $number--;
                        $avatar_skills_values{$skill} = "12+$number";
                    } else {
                        $avatar_skills_values{$skill} = 12;
                    }
                }
                update_display_avatar($avatar_skills_values{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
				if($skill eq "Nahkampf")
				{
					update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
				}
				elsif($skill eq "Konstitution")
				{
					update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
				}
            }
        )->grid(-row => $row, -column => 1, -sticky => 'e', -ipadx=> 8);
		update_display_avatar($avatar_skills_values{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
		if($skill eq "Nahkampf")
		{
			update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
		}
		elsif($skill eq "Konstitution")
		{
			update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
		}
        $row++;
    }

    # Abgeleitete Werte
    my $abglw_label = $avatar_dialog->Label(-text => "Abgeleitete Werte")->grid(-row => 5, -column => 2, -columnspan => 4);

    my $bewegung_label = $avatar_dialog->Label(-text => "Bewegung")->grid(-row => 6, -column => 2, -sticky => 'w');
    my $bewegung_basis = $avatar_dialog->Label(-width => 3, -text => 6)->grid(-row => 6, -column => 2, -sticky => 'n');
    my $bewegungmod_label = $avatar_dialog->Label(-width => 3, -text => "Mod")->grid(-row => 6, -column => 2, -sticky => 'e', -ipadx=> 10);
    my $bewegungmod_entry = $avatar_dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 6, -column => 3, -sticky => 'w');
    my $bewegungges_label = $avatar_dialog->Label(-text => "Gesamt")->grid(-row => 6, -column => 3, -sticky => 'n');
    my $bewegunggs_entry = $avatar_dialog->Label(-width => 3, -text => $bewegung_basis->cget('-text') . '"')->grid(-row => 6, -column => 3, -sticky => 'e');

    $bewegungmod_entry->bind('<KeyRelease>', sub {
        my $mod_value = $bewegungmod_entry->get();
        if ($mod_value =~ /^[\+-]?\d+$/)
        {
            $bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') + $mod_value . '"');
        }
        elsif ($mod_value =~ /^[\+-]?\d*$/)
        {
            $bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') . '"');
        }
        else
        {
            $avatar_dialog->messageBox(
                -type    => 'Ok',
                -icon    => 'error',
                -title   => 'Bewegungs-Mod fehlerhaft',
                -message => "Bitte den Wert im Mod-Feld bei Bewegung prüfen.\nSetze den Gesamt-Wert auf den Basis-Wert."
            );
            $bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') . '"');
        }
    });

    my $parade_label = $avatar_dialog->Label(-text => "Parade")->grid(-row => 7, -column => 2, -sticky => 'w');
    my $parademod_label = $avatar_dialog->Label(-width => 3, -text => "Mod")->grid(-row => 7, -column => 2, -sticky => 'e', -ipadx=> 10);
	$parademod_entry->bind('<KeyRelease>', sub { update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{'Nahkampf'}, $skill_mods{'Nahkampf'}); });
    my $paradeges_label = $avatar_dialog->Label(-text => "Gesamt")->grid(-row => 7, -column => 3, -sticky => 'n');

	$balloon->attach($parade_basis, -balloonmsg => "Basis: 2 + ((Nahkampf + Mod) / 2) + ((Reaktion Charakter über D6 + Mod) / 2) + ((Ausweichen Charakter + Mod) / 2), aufgerundet");
	$balloon->attach($paradegs_entry, -balloonmsg => "Gesamt: Basis + Modifikator");
	
    my $robust_label = $avatar_dialog->Label(-text => "Robustheit")->grid(-row => 8, -column => 2, -sticky => 'w');
    my $robustmod_label = $avatar_dialog->Label(-width => 3, -text => "Mod")->grid(-row => 8, -column => 2, -sticky => 'e', -ipadx=> 10);
    my $robustges_label = $avatar_dialog->Label(-text => "Gesamt")->grid(-row => 8, -column => 3, -sticky => 'n');

    $robustmod_entry->bind('<KeyRelease>', sub {
        update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
    });

    # Inventarverwaltung
    my $inventar_label = $avatar_dialog->Label(-text => "Inventarverwaltung")->grid(-row => 9, -column => 2, -columnspan => 2);

    # Charakterbild
    my $dirname = get_script_dir();

    unless (-e "$dirname/avatar.gif") {
        die "Fehler: Bilddatei avatar.gif konnte nicht gefunden werden.\n";
    }

    my $image = $avatar_dialog->Photo(-file => "$dirname/avatar.gif");
    my $canvas = $avatar_dialog->Canvas(
    -width  => 257,
    -height => 257
    )->grid(
    -row      => 10,
    -column   => 2,
    -rowspan  => 10,
    -columnspan  => 2,
    -sticky   => 'nsew'
    );
    $canvas->createImage(0, 0, -image => $image, -anchor => 'nw');

    my %waffenwerte = ();
    my %panzerwerte = ();

    $panzerwerte{Kopf}{name} = "Mütze";
    $panzerwerte{Kopf}{panzerung} = 0;
    $panzerwerte{Kopf}{kv} = -1;
    $panzerwerte{Kopf}{gewicht} = 0;
    $panzerwerte{Kopf}{kosten} = 0;
    $panzerwerte{Kopf}{anmerkungen} = "Eine bequeme Mütze";
    $panzerwerte{Arme}{name} = "Pullover";
    $panzerwerte{Arme}{panzerung} = 0;
    $panzerwerte{Arme}{kv} = -1;
    $panzerwerte{Arme}{gewicht} = 0;
    $panzerwerte{Arme}{kosten} = 0;
    $panzerwerte{Arme}{anmerkungen} = "Ein bequemer Pullover";
    $panzerwerte{Torso}{name} = "Pullover";
    $panzerwerte{Torso}{panzerung} = 0;
    $panzerwerte{Torso}{kv} = -1;
    $panzerwerte{Torso}{gewicht} = 0;
    $panzerwerte{Torso}{kosten} = 0;
    $panzerwerte{Torso}{anmerkungen} = "Ein bequemer Pullover";
    $panzerwerte{Beine}{name} = "Hose";
    $panzerwerte{Beine}{panzerung} = 0;
    $panzerwerte{Beine}{kv} = -1;
    $panzerwerte{Beine}{gewicht} = 0;
    $panzerwerte{Beine}{kosten} = 0;
    $panzerwerte{Beine}{anmerkungen} = "Eine bequeme Hose";

    $waffenwerte{"linke Hand"}{name} = "Nichts";
    $waffenwerte{"linke Hand"}{schaden} = "";
    $waffenwerte{"linke Hand"}{rw} = "";
    $waffenwerte{"linke Hand"}{kv} = -1;
    $waffenwerte{"linke Hand"}{gewicht} = "";
    $waffenwerte{"linke Hand"}{kosten} = "";
    $waffenwerte{"linke Hand"}{anmerkungen} = "";
    $waffenwerte{"linke Hand"}{pb} = "";
    $waffenwerte{"linke Hand"}{fr} = "";
    $waffenwerte{"linke Hand"}{schuss} = "";
    $waffenwerte{"linke Hand"}{flaeche} = "";
	$waffenwerte{"rechte Hand"}{kv} = -1;
	$waffenwerte{"rechte Hand"}{flaeche} = "";
	$waffenwerte{"rechte Hand"}{anmerkungen} = "";
	if($angriffstyp eq "Nahkampf")
	{
		$waffenwerte{"rechte Hand"}{name} = "Nahkampfwaffe 1W6";
		$waffenwerte{"rechte Hand"}{schaden} = "1W6";
		$waffenwerte{"rechte Hand"}{rw} = "";
		$waffenwerte{"rechte Hand"}{gewicht} = "1";
		$waffenwerte{"rechte Hand"}{kosten} = "100";
		$waffenwerte{"rechte Hand"}{pb} = "";
		$waffenwerte{"rechte Hand"}{fr} = "";
		$waffenwerte{"rechte Hand"}{schuss} = "";
	}
	elsif($angriffstyp eq "Fernkampf")
	{
		$waffenwerte{"rechte Hand"}{typ} = "Fernkampf";
		$waffenwerte{"rechte Hand"}{name} = "Fernkampfwaffe 2W6";
		$waffenwerte{"rechte Hand"}{schaden} = "2W6";
		$waffenwerte{"rechte Hand"}{rw} = "12/24/48";
		$waffenwerte{"rechte Hand"}{gewicht} = "1,5";
		$waffenwerte{"rechte Hand"}{kosten} = "250";
		$waffenwerte{"rechte Hand"}{pb} = "0";
		$waffenwerte{"rechte Hand"}{fr} = "1";
		$waffenwerte{"rechte Hand"}{schuss} = "1";
	}
	else
	{
		$waffenwerte{"rechte Hand"}{name} = "Nichts";
		$waffenwerte{"rechte Hand"}{schaden} = "";
		$waffenwerte{"rechte Hand"}{rw} = "";
		$waffenwerte{"rechte Hand"}{gewicht} = "";
		$waffenwerte{"rechte Hand"}{kosten} = "";
		$waffenwerte{"rechte Hand"}{pb} = "";
		$waffenwerte{"rechte Hand"}{fr} = "";
		$waffenwerte{"rechte Hand"}{schuss} = "";
	}

    # Definieren der Bereiche für Körperteile (angepasste Koordinaten)
    my $head_coords = [114, 11, 144, 44];
    my $body_coords = [104, 45, 153, 123];
    my $right_arm_coords = [54, 32, 103, 63];
    my $left_arm_coords = [154, 32, 203, 60];
    my $beine_coords = [97, 124, 162, 226];
    my $left_hand_coords = [204, 32, 237, 60];
    my $right_hand_coords = [21, 32, 53, 60];

    # Erstellen der Klickbereiche
    create_clickable_area($head_coords, 'head', $canvas);
    create_clickable_area($body_coords, 'body', $canvas);
    create_clickable_area($left_arm_coords, 'left_arm', $canvas);
    create_clickable_area($right_arm_coords, 'right_arm', $canvas);
    create_clickable_area($beine_coords, 'beine', $canvas);
    create_clickable_area($left_hand_coords, 'left_hand', $canvas);
    create_clickable_area($right_hand_coords, 'right_hand', $canvas);

    # Ereignishandler für Klicks auf die Körperteile
    $row++;
    my $kopf_label = $avatar_dialog->Label(-text => "Kopf")->grid(-row => 11, -column => 3, -sticky => 'e');
    my $kopf_entry = $avatar_dialog->Label(-text => "$panzerwerte{Kopf}{name}, P $panzerwerte{Kopf}{panzerung}")->grid(-row => 11, -column => 4, -sticky => 'w', -columnspan => 5);
    my $arme_label = $avatar_dialog->Label(-text => "Arme")->grid(-row => 12, -column => 3, -sticky => 'e');
    my $arme_entry = $avatar_dialog->Label(-text => "$panzerwerte{Arme}{name}, P $panzerwerte{Arme}{panzerung}")->grid(-row => 12, -column => 4, -sticky => 'w', -columnspan => 5);
    my $lhand_label = $avatar_dialog->Label(-text => "Linke Hand")->grid(-row => 13, -column => 3, -sticky => 'e');
    my $lhand_entry = $avatar_dialog->Label(-text => "Nichts")->grid(-row => 13, -column => 4, -sticky => 'w', -columnspan => 5);
    my $rhand_label = $avatar_dialog->Label(-text => "Rechte Hand")->grid(-row => 14, -column => 3, -sticky => 'e');
	my $rhand_entry;
	if($angriffstyp eq 'Nahkampf')
	{
		$rhand_entry = $avatar_dialog->Label(-text => "Nahkampfwaffe 1W6")->grid(-row => 14, -column => 4, -sticky => 'w', -columnspan => 5);
	}
	elsif($angriffstyp eq 'Fernkampf')
	{
		$rhand_entry = $avatar_dialog->Label(-text => "Fernkampfwaffe 2W6")->grid(-row => 14, -column => 4, -sticky => 'w', -columnspan => 5);
	}
	else
	{
		$rhand_entry = $avatar_dialog->Label(-text => "Nichts")->grid(-row => 14, -column => 4, -sticky => 'w', -columnspan => 5);
	}
    my $torso_label = $avatar_dialog->Label(-text => "Torso")->grid(-row => 15, -column => 3, -sticky => 'e');
    my $torso_entry = $avatar_dialog->Label(-text => "$panzerwerte{Torso}{name}, P $panzerwerte{Torso}{panzerung}")->grid(-row => 15, -column => 4, -sticky => 'w', -columnspan => 5);
    my $beine_label = $avatar_dialog->Label(-text => "Beine")->grid(-row => 16, -column => 3, -sticky => 'e');
    my $beine_entry = $avatar_dialog->Label(-text => "$panzerwerte{Beine}{name}, P $panzerwerte{Beine}{panzerung}")->grid(-row => 16, -column => 4, -sticky => 'w', -columnspan => 5);
	
	my %notizen = (notizen => '');
	my $notizen_button = $avatar_dialog->Button(-text => "Notizen", -command => sub{open_notizen_window(\%notizen, $avatar_dialog)})->grid(-row => 18, -column => 4, -sticky => 'w', -columnspan => 5);

    $canvas->bind('head', '<Button-1>', sub { update_item_label($avatar_dialog, 'Kopf', $kopf_entry, \%panzerwerte) });
    $canvas->bind('body', '<Button-1>', sub { update_item_label($avatar_dialog, 'Torso', $torso_entry, \%panzerwerte) });
    $canvas->bind('left_arm', '<Button-1>', sub { update_item_label($avatar_dialog, 'Arme', $arme_entry, \%panzerwerte) });
    $canvas->bind('right_arm', '<Button-1>', sub { update_item_label($avatar_dialog, 'Arme', $arme_entry, \%panzerwerte) });
    $canvas->bind('beine', '<Button-1>', sub { update_item_label($avatar_dialog, 'Beine', $beine_entry, \%panzerwerte) });
    $canvas->bind('left_hand', '<Button-1>', sub { update_weapon_label($avatar_dialog, 'linke Hand', $lhand_entry, \%waffenwerte) });
    $canvas->bind('right_hand', '<Button-1>', sub { update_weapon_label($avatar_dialog, 'rechte Hand', $rhand_entry, \%waffenwerte) });

    my %wissen_skills = ();
	$wissen_skills{$welt} = 4;
	my $verstand_benutzt = -1;
    my $wissen_button = $avatar_dialog->Button(
        -text => "Wissensfertigkeiten",
        -command => sub {
            manage_wissen_skills("Fertigkeitspunkte", $avatar_dialog, \%wissen_skills, \$verstand_benutzt, -1, $skillpunkt_entry);
        }
    )->grid(-row => $row - 3, -column => 2);

    # Vermögen
    my $vermoegen_label  = $avatar_dialog->Label(-text => "Vermögen")->grid(-row => $row - 2, -column => 2);
    my $vermoegen_entry = $avatar_dialog->Entry(-textvariable => 0)->grid(-row => $row - 2, -column => 3, -sticky => 'w');

    # Inventarslots
    my $inventarslots_label  = $avatar_dialog->Label(-text => "Inventarslots")->grid(-row => $row - 1, -column => 2);
    my $inventarslots_entry = $avatar_dialog->Label(-text => 10)->grid(-row => $row - 1, -column => 3, -sticky => 'w');

    # Talents
    my $talent_frame = create_talent_frame($talentpunkt_entry, $avatar_dialog, $row);
	$talent_frame->insert('end', 'Machtnutzung') if($angriffstyp eq 'Machtnutzung');

    # Gegenstände
    my $items_label = $avatar_dialog->Label(-text => "Ausrüstung")->grid(-row => $row, -column => 2);
    $row++;
    my $items_listbox = $avatar_dialog->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->grid(-row => $row, -column => 2, -sticky => 'w');
    $items_listbox->Subwidget('listbox')->bind('<Enter>', sub{$items_listbox->Subwidget('listbox')->focus()});
    $items_listbox->Subwidget('listbox')->bind('<Leave>', sub {$avatar_dialog->focus();});

    my $items_button_frame = $avatar_dialog->Frame()->grid(-row => $row, -column => 3, -sticky => 'w');
    $items_button_frame->Button(
        -text => "+",
        -command => sub { add_items_item($avatar_dialog, $items_listbox, 10, 'Gegenstand') }
    )->pack(-side => 'top');
    $items_button_frame->Button(
        -text => "-",
        -command => sub { delete_items_item($avatar_dialog, $items_listbox) }
    )->pack(-side => 'top');
	
	$row += 2;
	
	# Handicaps
    my $handicap_frame = create_handicap_frame($talentpunkt_entry, $avatar_dialog, $row);
	
	# Mächte
    my $maechte_label = $avatar_dialog->Label(-text => "Mächte")->grid(-row => $row, -column => 2);
    $row++;
    my $maechte_listbox = $avatar_dialog->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->grid(-row => $row, -column => 2, -sticky => 'w');
    $maechte_listbox->Subwidget('listbox')->bind('<Enter>', sub{$maechte_listbox->Subwidget('listbox')->focus()});
    $maechte_listbox->Subwidget('listbox')->bind('<Leave>', sub {$avatar_dialog->focus();});

    my $maechte_button_frame = $avatar_dialog->Frame()->grid(-row => $row, -column => 3, -sticky => 'w');
    $maechte_button_frame->Button(
        -text => "+",
        -command => sub { add_items_item($avatar_dialog, $maechte_listbox, 0, 'Macht') }
    )->pack(-side => 'top');
    $maechte_button_frame->Button(
        -text => "-",
        -command => sub { delete_items_item($avatar_dialog, $maechte_listbox) }
    )->pack(-side => 'top');

    $row+=2;

    # Save Button
    $avatar_dialog->Button(
        -text    => "Speichern",
        -command => sub {
			if($skillpunkt_entry->cget('-text') != 0 || $talentpunkt_entry->cget('-text') != 0)
			{
				$avatar_dialog->messageBox(
				-type    => 'Ok',
				-icon    => 'info',
				-title   => 'Punkte verteilen',
				-message => "Bitte erst alle Talent- & Fertigkeits-Punkte verteilen!"
				);
			}
			else
			{
				my @avatar_talents = $talent_frame->get(0, 'end');
				my @avatar_handicaps = $handicap_frame->get(0, 'end');
				push @$avatars_ref, {
					name      => $name_entry->get(),
					vermoegen      => $vermoegen_entry->get(),
					game      => $game_entry->get(),
					description      => $description_entry->get(),
					gilden    => $gilden_entry->get(),
					xp => 0,
					machttrank => 0,
					heiltrank => 0,
					steigerungspunkte => 0,
					inventarslots => 10,
					notizen => $notizen{notizen},
					bennies     => $bennies_entry->get(),
					benniesmax     => $benniesmax_entry->get(),
					wunden      => $wunden_entry->get(),
					wundenmax      => $wundenmax_entry->get(),
					bewegungmod => $bewegungmod_entry->get(),
					parademod   => $parademod_entry->get(),
					robustmod   => $robustmod_entry->get(),
					mp          => $mp_entry->get(),
					rank      => 'Anfänger',
					level      => 0,
					skills    => { %avatar_skills_values },
					skill_mods => { %skill_mods },
					wissen    => { %wissen_skills },
					talents   => [@avatar_talents],
					items   => [$items_listbox->get(0, 'end')],
					maechte   => [$maechte_listbox->get(0, 'end')],
					handicaps => [@avatar_handicaps],
					panzer  => { %panzerwerte },
					waffen  => { %waffenwerte }
				};

				# Update the Listbox only if the data has changed
				$avatar_listbox->insert('end', $name_entry->get() . ' (' . $game_entry->get() . ')');
				$parent_dialog->focus();
				$add_avatar->destroy();
			}
		}
    )->grid(-row => $row, -column => 1);
}

sub edit_avatar {
    my ($parent_dialog, $avatars_ref, $avatar_listbox, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods) = @_;

    my $selected = $avatar_listbox->curselection();
    unless (defined $selected) {
        $parent_dialog->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Avatar wählen',
            -message => "Bitte einen Avatar auswählen."
        );
        return;
    }
    my $index = $selected->[0];

    my $avatar = $avatars_ref->[$index];

    my $edit_avatar = $parent_dialog->Toplevel();
    focus_dialog($edit_avatar, "Avatar bearbeiten", $parent_dialog);
    my $scrolled_area = $edit_avatar->Scrolled(
        'Frame',
        -scrollbars => 'osoe' # Scrollbars nur rechts/unten bei Bedarf
    )->pack(-fill => 'both', -expand => 1); # Füllt das gesamte Dialogfenster

    # --- NEU: Der eigentliche Inhalts-Frame ---
    my $edit_dialog = $scrolled_area->Subwidget('scrolled');
	
	if($index == 0)
	{
		$edit_avatar->geometry("300x100");  # Set window size
		# Name
		my $name_label = $edit_dialog->Label(-text => "Avatar-Name")->grid(-row => 0, -column => 0, -sticky => 'w');
		my $name_entry = $edit_dialog->Entry(-textvariable => \$avatar->{name})->grid(-row => 0, -column => 1, -sticky => 'w');
		# Beschreibung
		my $description_label = $edit_dialog->Label(-text => "Beschreibung")->grid(-row => 1, -column => 0, -sticky => 'w');
		my $description_entry = $edit_dialog->Entry(-textvariable => \$avatar->{description})->grid(-row => 1, -column => 1, -sticky => 'w');
		$edit_dialog->Button(
			-text    => "Speichern",
			-command => sub {
				$avatar->{name} = $name_entry->get();
				$avatar->{description} = $description_entry->get();
				$avatar_listbox->delete($index);
				$avatar_listbox->insert($index, $avatar->{name} . ' (' . $avatar->{game} . ')');
				$edit_avatar->destroy();
			}
		)->grid(-row => 2, -column => 1, -sticky => 'w');
	}
	else
	{
		$edit_avatar->geometry("950x800");  # Set window size
		my $spacer = $edit_dialog->Label(-text => "", -width => 42)->grid(-row => 0, -column => 0);
		my $balloon = $edit_dialog->Balloon();
		
		my %skill_mods = %{$avatar->{skill_mods}};
		my %avatar_skills_values = %{$avatar->{skills}};
		my %skills_fields = ();
		
		my $row = 0;

		# Avatar Name
		my $name_label = $edit_dialog->Label(-text => "Avatar-Name")->grid(-row => $row, -column => 0, -sticky => 'w');
		my $name_entry = $edit_dialog->Entry(-textvariable => \$avatar->{name})->grid(-row => $row, -column => 1, -sticky => 'w');

		# XP
		my $xp_label = $edit_dialog->Label(-text => "Erfahrungspunkte")->grid(-row => $row, -column => 2, -sticky => 'w');
		my $xp_entry = $edit_dialog->Label(-text => $avatar->{xp})->grid(-row => $row, -column => 2, -sticky => 'e');

		
		# Steigerungspunkte über
		my $sp_label = $edit_dialog->Label(-text => "Steigerungspunkte")->grid(-row => $row, -column => 3, -sticky => 'w');
		my $sp_entry = $edit_dialog->Label(-text => $avatar->{steigerungspunkte})->grid(-row => $row, -column => 3, -sticky => 'e');
		$row++;

		# Game
		my $game_label = $edit_dialog->Label(-text => "Welt")->grid(-row => $row, -column => 0, -sticky => 'w');
		my $game_entry = $edit_dialog->Entry(-textvariable => \$avatar->{game})->grid(-row => $row, -column => 1, -sticky => 'w');

		# Rank
		my $rank_label = $edit_dialog->Label(-text => "Rang")->grid(-row => $row, -column => 2, -sticky => 'w');
		my $rank_entry = $edit_dialog->Label(-width => 11, -text => $avatar->{rank})->grid(-row => $row, -column => 2, -sticky => 'e');
		
		# Parade
		my $parade_label = $edit_dialog->Label(-text => "Parade")->grid(-row => 7, -column => 2, -sticky => 'w');
		my $parade_basis = $edit_dialog->Label(-width => 3, -text => 2)->grid(-row => 7, -column => 2, -sticky => 'n');
		my $parademod_label = $edit_dialog->Label(-width => 3, -text => "Mod")->grid(-row => 7, -column => 2, -sticky => 'e', -ipadx => 10);
		my $parademod_entry = $edit_dialog->Entry(-width => 3, -textvariable => \$avatar->{parademod}, -validate => 'key', -validatecommand => sub {
			my $new_value = shift;
			return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
			return 0;
		})->grid(-row => 7, -column => 3, -sticky => 'w');
		my $paradeges_label = $edit_dialog->Label(-text => "Gesamt")->grid(-row => 7, -column => 3, -sticky => 'n');
		my $paradegs_entry = $edit_dialog->Label(-width => 3)->grid(-row => 7, -column => 3, -sticky => 'e');
		$parademod_entry->bind('<KeyRelease>', sub { update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{'Nahkampf'}, $skill_mods{'Nahkampf'}); });

		$balloon->attach($parade_basis, -balloonmsg => "Basis: 2 + ((Nahkampf + Mod) / 2) + ((Reaktion Charakter über D6 + Mod) / 2) + ((Ausweichen Charakter + Mod) / 2), aufgerundet");
		$balloon->attach($paradegs_entry, -balloonmsg => "Gesamt: Basis + Modifikator");
		
		#Robustheit
		my $robust_label = $edit_dialog->Label(-text => "Robustheit")->grid(-row => 8, -column => 2, -sticky => 'w');
		my $robust_basis = $edit_dialog->Label(-width => 3)->grid(-row => 8, -column => 2, -sticky => 'n');
		my $robustmod_label = $edit_dialog->Label(-width => 3, -text => "Mod")->grid(-row => 8, -column => 2, -sticky => 'e', -ipadx => 10);
		my $robustmod_entry = $edit_dialog->Entry(-width => 3, -textvariable => $avatar->{robustmod}, -validate => 'key', -validatecommand => sub {
			my $new_value = shift;
			return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
			return 0;
		})->grid(-row => 8, -column => 3, -sticky => 'w');
		my $robustges_label = $edit_dialog->Label(-text => "Gesamt")->grid(-row => 8, -column => 3, -sticky => 'n');
		my $robustgs_entry = $edit_dialog->Label(-width => 3)->grid(-row => 8, -column => 3, -sticky => 'e');
			$robustmod_entry->bind('<KeyRelease>', sub {
			update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
		});

		# XP hinzufügen
		my $level_entry;
		my $inventarslots_entry;

		my $machttrank_entry;
		my $heiltrank_entry;
		my $xp_add = $edit_dialog->Button(
			-text => "Erfahrungspunkte hinzufügen",
			-command => sub
			{
				my $input_window = $edit_dialog->Toplevel;
				$input_window->configure(-width => 400);
				focus_dialog($input_window, "XP hinzufügen", $parent_dialog);
				my $xp_added = 0;
				my $label_xp = $input_window->Label(-text => "Hinzugewonnene Erfahrungspunkte:")->pack;
				my $entry_xp = $input_window->Entry(-textvariable => \$xp_added, -validate => 'key', -validatecommand => sub {
					my $new_value = shift;
					return 1 if($new_value =~ /^\d+$/);
					return 0;
				})->pack;

				my $button_submit = $input_window->Button(
					-text => "OK",
					-command => sub
					{
						$edit_dialog->update;
						$input_window->update;
						$mw->update;
						$input_window->bind('<Escape>', sub { $input_window->destroy });
						if ($xp_added =~ /^\d+$/)
						{
							if(defined $xp_added && $xp_added > 0)
							{
								unless($level_entry->cget('-text') == 100)
								{
									$xp_entry->configure(-text =>$xp_entry->cget('-text') + $xp_added);
									my $new_level = $level_entry->cget('-text');
									my @levels = (
										{ level => 0, total_xp => 0 }, # Startlevel - kein Bonus
										{ level => 1, total_xp => 1000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 2, total_xp => 3000, bonus => { Heiltrank => 1 } }, # Alle 24h gratis ein Heiltrank
										{ level => 3, total_xp => 7500, bonus => { Gold => 1000 } }, # + 1000 Gold
										{ level => 4, total_xp => 15500, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 5, total_xp => 28000, bonus => { Gold => 1200 } }, # + 1200 Gold
										{ level => 6, total_xp => 46000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 7, total_xp => 70500, bonus => { Gold => 1400 } }, # + 1400 Gold
										{ level => 8, total_xp => 102500, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 9, total_xp => 143000, bonus => { Gold => 1600 } }, # + 1600 Gold
										{ level => 10, total_xp => 193000, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 11, total_xp => 253500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 12, total_xp => 325500, bonus => { Trank => 1 } }, # Alle 24h gratis ein Heil- oder Machttrank
										{ level => 13, total_xp => 410000, bonus => { Gold => 1800 } }, # + 1800 Gold
										{ level => 14, total_xp => 508000, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 15, total_xp => 620500, bonus => { Gold => 2000 } }, # + 2000 Gold
										{ level => 16, total_xp => 748500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 17, total_xp => 893000, bonus => { Gold => 2200 } }, # + 2200 Gold
										{ level => 18, total_xp => 1055000, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 19, total_xp => 1235500, bonus => { Gold => 2400 } }, # + 2400 Gold
										{ level => 20, total_xp => 1435500, bonus => { Kosmetikitem => 1, Rank => 'Fortgeschritten' } }, # Ein besonderes kosmetisches Item
										{ level => 21, total_xp => 1656000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 22, total_xp => 1898000, bonus => { Heiltrank => 1 } }, # Alle 24h gratis ein Heiltrank
										{ level => 23, total_xp => 2162500, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 24, total_xp => 2450500, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 25, total_xp => 2763000, bonus => { Gold => 2600 } }, # + 2600 Gold
										{ level => 26, total_xp => 3101000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 27, total_xp => 3465500, bonus => { Gold => 2700 } }, # + 2700 Gold
										{ level => 28, total_xp => 3857500, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 29, total_xp => 4278000, bonus => { Gold => 2800 } }, # + 2800 Gold
										{ level => 30, total_xp => 4728000, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 31, total_xp => 5208500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 32, total_xp => 5720500, bonus => { Trank => 1 } }, # Alle 24h gratis ein Heil- oder Machttrank
										{ level => 33, total_xp => 6265000, bonus => { Gold => 3000 } }, # + 3000 Gold
										{ level => 34, total_xp => 6843000, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 35, total_xp => 7455500, bonus => { Gold => 3200 } }, # + 3200 Gold
										{ level => 36, total_xp => 8103500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 37, total_xp => 8788000, bonus => { Gold => 3400 } }, # + 3400 Gold
										{ level => 38, total_xp => 9510000, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 39, total_xp => 10270500, bonus => { Gold => 3600 } }, # + 3600 Gold
										{ level => 40, total_xp => 11070500, bonus => { Kosmetikitem => 1, Rank => 'Vetran' } }, # Ein besonderes kosmetisches Item
										{ level => 41, total_xp => 11911000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 42, total_xp => 12793000, bonus => { Heiltrank => 1 } }, # Alle 24h gratis ein Heiltrank
										{ level => 43, total_xp => 13717500, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 44, total_xp => 14685500, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 45, total_xp => 15698000, bonus => { Gold => 3800 } }, # + 3800 Gold
										{ level => 46, total_xp => 16756000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte...
										{ level => 47, total_xp => 17860500, bonus => { Gold => 4000 } }, # + 4000 Gold
										{ level => 48, total_xp => 19012500, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 49, total_xp => 20213000, bonus => { Gold => 4200 } }, # + 4200 Gold
										{ level => 50, total_xp => 21463000, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 51, total_xp => 22763500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (über d10)
										{ level => 52, total_xp => 24115500, bonus => { Trank => 1 } }, # Alle 24h gratis ein Heil- oder Machttrank
										{ level => 53, total_xp => 25520000, bonus => { Gold => 4400 } }, # + 4400 Gold
										{ level => 54, total_xp => 26978000, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 55, total_xp => 28490500, bonus => { Gold => 4600 } }, # + 4600 Gold
										{ level => 56, total_xp => 30058500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (auf d10+)
										{ level => 57, total_xp => 31683000, bonus => { Gold => 4800 } }, # + 4800 Gold
										{ level => 58, total_xp => 33365000, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 59, total_xp => 35105500, bonus => { Gold => 5000 } }, # + 5000 Gold
										{ level => 60, total_xp => 36905500, bonus => { Kosmetikitem => 1, Rank => 'Heroisch' } }, # Ein besonderes kosmetisches Item
										{ level => 61, total_xp => 38766000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (über d10)
										{ level => 62, total_xp => 40688000, bonus => { Heiltrank => 1 } }, # Alle 24h gratis ein Heiltrank
										{ level => 63, total_xp => 42672500, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 64, total_xp => 44720500, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 65, total_xp => 46833000, bonus => { Gold => 5200 } }, # + 5200 Gold
										{ level => 66, total_xp => 49011000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (auf d10+)
										{ level => 67, total_xp => 51255500, bonus => { Gold => 5400 } }, # + 5400 Gold
										{ level => 68, total_xp => 53567500, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 69, total_xp => 55948000, bonus => { Gold => 5600 } }, # + 5600 Gold
										{ level => 70, total_xp => 58398000, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 71, total_xp => 60918500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (über d10)
										{ level => 72, total_xp => 63510500, bonus => { Trank => 1 } }, # Alle 24h gratis ein Heil- oder Machttrank
										{ level => 73, total_xp => 66175000, bonus => { Gold => 5800 } }, # + 5800 Gold
										{ level => 74, total_xp => 68913000, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 75, total_xp => 71725500, bonus => { Gold => 6000 } }, # + 6000 Gold
										{ level => 76, total_xp => 74613500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (auf d10+)
										{ level => 77, total_xp => 77578000, bonus => { Gold => 6200 } }, # + 6200 Gold
										{ level => 78, total_xp => 80620000, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 79, total_xp => 83740500, bonus => { Gold => 6400 } }, # + 6400 Gold
										{ level => 80, total_xp => 86940500, bonus => { Kosmetikitem => 1, Rank => 'Legendär' } }, # Ein besonderes kosmetisches Item
										{ level => 81, total_xp => 90221000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (über d10)
										{ level => 82, total_xp => 93583000, bonus => { Heiltrank => 1 } }, # Alle 24h gratis ein Heiltrank
										{ level => 83, total_xp => 97027500, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 84, total_xp => 100555500, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 85, total_xp => 104168000, bonus => { Gold => 6600 } }, # + 6600 Gold
										{ level => 86, total_xp => 107866000, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (auf d10+)
										{ level => 87, total_xp => 111650500, bonus => { Gold => 6800 } }, # + 6800 Gold
										{ level => 88, total_xp => 115522500, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 89, total_xp => 119483000, bonus => { Gold => 7000 } }, # + 7000 Gold
										{ level => 90, total_xp => 123533000, bonus => { Verteidigung => 1 } }, # + 1 auf Parade oder Robustheit
										{ level => 91, total_xp => 127673500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (über d10)
										{ level => 92, total_xp => 131905500, bonus => { Trank => 1 } }, # Alle 24h gratis ein Heil- oder Machttrank
										{ level => 93, total_xp => 136230000, bonus => { Gold => 7500 } }, # + 7500 Gold
										{ level => 94, total_xp => 140648000, bonus => { ItemSlot => 1 } }, # + 1 Item-Slot
										{ level => 95, total_xp => 145160500, bonus => { Gold => 8000 } }, # + 8000 Gold
										{ level => 96, total_xp => 149768500, bonus => { Steigerungspunkte => 2 } }, # 1 Talentpunkt oder zwei Fertigkeitspunkte... (auf d10+)
										{ level => 97, total_xp => 154473000, bonus => { Gold => 9000 } }, # + 9000 Gold
										{ level => 98, total_xp => 159275000, bonus => { Angriffsart => 1 } }, # +1 auf eine der folgenden Angriffsarten...
										{ level => 99, total_xp => 164175500, bonus => { Gold => 10000 } }, # + 10000 Gold
										{ level => 100, total_xp => 169175500, bonus => { Kosmetikitem => 1, ItemSlot => 1 } }, # Ein besonderes kosmetisches Item +1 Item-Slot
									);

									my %boni = ();
									for(my $i = $level_entry->cget('-text') + 1; $i <= $#levels; $i++)
									{
										if($xp_entry->cget('-text') < $levels[$i]->{total_xp})
										{
											$new_level = $i - 1;
											last;
										}
										else
										{
											foreach my $bonus (keys %{$levels[$i]->{bonus}})
											{
												if($bonus eq 'Rank')
												{
													$boni{Rank} = $levels[$i]->{bonus}{Rank};
												}
												else
												{
													$boni{$bonus} += $levels[$i]->{bonus}{$bonus};
												}
											}
										}
									}
									$new_level = 100 if($level_entry->cget('-text') < 100 && $xp_entry->cget('-text') > $levels[-1]->{total_xp});
									if($new_level > $level_entry->cget('-text'))
									{
										my $boni_msg = "";
										my $selectable_bonus_value  = 0;
										my %bonuses_to_distribute;
										foreach my $bonus (sort keys %boni)
										{
											if($bonus eq 'Steigerungspunkte')
											{
												$sp_entry->configure(-text => $sp_entry->cget('-text') + $boni{$bonus});
												$boni_msg .= "\n$boni{$bonus} Steigerungspunkte";
											}
											elsif($bonus eq 'Rank')
											{
												$rank_entry->configure(-text => $boni{Rank});
												$boni_msg = "\nNeuer Rank: $boni{Rank}$boni_msg";
											}
											elsif($bonus eq 'Kosmetikitem')
											{
												if($boni{Kosmetikitem} > 1)
												{
													$boni_msg .= "\n$boni{Kosmetikitem} kosmetische Gegenstände";
												}
												else
												{
													$boni_msg .= "\nEinen kosmetischen Gegenstand";
												}
											}
											elsif($bonus eq 'Gold')
											{
												$avatar->{vermoegen} += $boni{Gold};
												$boni_msg .= "\n$boni{Gold} Vermögen";
											}
											elsif($bonus eq 'Heiltrank')
											{
												$heiltrank_entry->configure(-text => $heiltrank_entry->cget('-text') + $boni{Heiltrank});
												if($boni{Heiltrank} > 1)
												{
													$boni_msg .= "\n$boni{Heiltrank} Heiltränke zur täglichen Verwendung";
												}
												else
												{
													$boni_msg .= "\nEin Heiltrank zur täglichen Verwendung";
												}
											}
											elsif($bonus eq 'ItemSlot')
											{
												$inventarslots_entry->configure(-text => $inventarslots_entry->cget('-text') + $boni{ItemSlot});
												if($boni{ItemSlot} > 1)
												{
													$boni_msg .= "\n$boni{ItemSlot} weitere Inventarslots";
												}
												else
												{
													$boni_msg .= "\nEinen weiteren Inventarslot";
												}
											}
											else
											{
												$bonuses_to_distribute{$bonus} = $boni{$bonus};
												$selectable_bonus_value += $boni{$bonus};
											}
										}
										if ($selectable_bonus_value > 0)
										{
											 my $after_popup_code = sub
											 {
												my ($status, $result_ref) = @_;
												if ($status eq 'ok')
												{
													if(defined $result_ref->{Trank} && defined $result_ref->{Trank}{Heiltrank} && $result_ref->{Trank}{Heiltrank} > 0)
													{
														$heiltrank_entry->configure(-text => $heiltrank_entry->cget('-text') + $result_ref->{Trank}{Heiltrank});
													}
													if(defined $result_ref->{Trank} && defined $result_ref->{Trank}{Machttrank} && $result_ref->{Trank}{Machttrank} > 0)
													{
														$machttrank_entry->configure(-text => $machttrank_entry->cget('-text') + $result_ref->{Trank}{Machttrank});
													}
													if(defined $result_ref->{Verteidigung} && defined $result_ref->{Verteidigung}{Robustheit} && $result_ref->{Verteidigung}{Robustheit} > 0)
													{
														my $entry_value = $robustmod_entry->get() + $result_ref->{Verteidigung}{Robustheit};
														$robustmod_entry->delete(0, 'end');
														$robustmod_entry->insert(0, $entry_value);
														update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
													}
													if(defined $result_ref->{Verteidigung} && defined $result_ref->{Verteidigung}{Parade} && $result_ref->{Verteidigung}{Parade} > 0)
													{
														my $entry_value = $parademod_entry->get() + $result_ref->{Verteidigung}{Parade};
														$parademod_entry->delete(0, 'end');
														$parademod_entry->insert(0, $entry_value);
														update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
													}
													if(defined $result_ref->{Angriffsart} && defined $result_ref->{Angriffsart}{Nahkampf} && $result_ref->{Angriffsart}{Nahkampf} > 0)
													{
														my $entry_value = $skills_fields{Nahkampf}{skillmod_entry}->get() + $result_ref->{Angriffsart}{Nahkampf};
														$skills_fields{Nahkampf}{skillmod_entry}->delete(0, 'end');
														$skills_fields{Nahkampf}{skillmod_entry}->insert(0, $entry_value);
														update_display_avatar($avatar_skills_values{Nahkampf}, $skills_fields{Nahkampf}{skillmod_entry}->get(), $skills_fields{Nahkampf}{entry}, 'Nahkampf', $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
														update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
													}
													if(defined $result_ref->{Angriffsart} && defined $result_ref->{Angriffsart}{Fernkampf} && $result_ref->{Angriffsart}{Fernkampf} > 0)
													{
														my $entry_value = $skills_fields{Fernkampf}{skillmod_entry}->get() + $result_ref->{Angriffsart}{Fernkampf};
														$skills_fields{Fernkampf}{skillmod_entry}->delete(0, 'end');
														$skills_fields{Fernkampf}{skillmod_entry}->insert(0, $entry_value);
														update_display_avatar($avatar_skills_values{Fernkampf}, $skills_fields{Fernkampf}{skillmod_entry}->get(), $skills_fields{Fernkampf}{entry}, 'Fernkampf', $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
													}
													if(defined $result_ref->{Angriffsart} && defined $result_ref->{Angriffsart}{Machtnutzung} && $result_ref->{Angriffsart}{Machtnutzung} > 0)
													{
														my $entry_value = $skills_fields{Machtnutzung}{skillmod_entry}->get() + $result_ref->{Angriffsart}{Machtnutzung};
														$skills_fields{Machtnutzung}{skillmod_entry}->delete(0, 'end');
														$skills_fields{Machtnutzung}{skillmod_entry}->insert(0, $entry_value);
														update_display_avatar($avatar_skills_values{Machtnutzung}, $skills_fields{Machtnutzung}{skillmod_entry}->get(), $skills_fields{Machtnutzung}{entry}, 'Machtnutzung', $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
													}
												}
												else
												{
													# Benutzer hat Abbrechen oder 'X' gedrückt (und ggf. bestätigt)
													$edit_dialog->messageBox(
														-title => "Abgebrochen",
														-message => "Die Verteilung der Level-Up-Punkte wurde abgebrochen.",
														-icon => 'warning'
													);
												}
											};

											# Zeige das Popup und übergebe Referenzen
											show_combined_distribution_popup(
											parent       => $edit_dialog,
											title        => 'Level-Up Boni verteilen',
											message      => "Du bist von Level " . $level_entry->cget('-text') . " auf Level $new_level aufgestiegen! Folgende Boni hast du erhalten:\n" . $boni_msg,
											bonuses_data => \%bonuses_to_distribute,
											on_close_callback => $after_popup_code # <<< Callback übergeben
											);
										}
										else
										{
											# Es gab keine Punkte zu verteilen, nur Info anzeigen
											 $edit_dialog->messageBox(
												 -title => "Level-Up!",
												 -message => "Du bist von Level " . $level_entry->cget('-text') . " auf Level $new_level aufgestiegen!\n" . $boni_msg,
												 -icon => 'info'
											 );
										}
										$level_entry->configure(-text => $new_level);
									}
								}
							}
							$input_window->destroy;
						}
						else
						{
							 # Zeige eine Fehlermeldung, wenn der Wert ungültig ist (z.B. leer oder nur '-')
							 $input_window->messageBox(-title => "Ungültige Eingabe", -message => "Bitte geben Sie eine gültige Zahl ein.", -type => 'ok', -icon => 'warning');
						}
					}
				)->pack;
				$input_window->bind('<Return>', sub { $button_submit->invoke });
			}
		)->grid(-row => $row, -column => 3, -sticky => 'w');

		$row++;

		# Beschreibung
		my $description_label = $edit_dialog->Label(-text => "Beschreibung")->grid(-row => $row, -column => 0, -sticky => 'w');
		my $description_entry = $edit_dialog->Entry(-textvariable => \$avatar->{description})->grid(-row => $row, -column => 1, -sticky => 'w');

		# Level
		my $level_label  = $edit_dialog->Label(-text => "Level")->grid(-row => $row, -column => 2, -sticky => 'w');
		$level_entry = $edit_dialog->Label(-text => $avatar->{level})->grid(-row => $row, -column => 2, -sticky => 'e');
		
		$row++;

		# Gilden
		my $gilden_label = $edit_dialog->Label(-text => "Gildenzugehörigkeit")->grid(-row => $row, -column => 0, -sticky => 'w');
		my $gilden_entry = $edit_dialog->Entry(-textvariable => \$avatar->{gilden})->grid(-row => $row, -column => 1, -sticky => 'w');

		# Bennies
		my $bennies_label = $edit_dialog->Label(-text => "Bennies")->grid(-row => $row, -column => 2, -sticky => 'w');
		my $bennies_entry = $edit_dialog->Entry(-width => 2, -textvariable => \$avatar->{bennies})->grid(-row => $row, -column => 2, -sticky => 'n');
		my $benniesmax_label = $edit_dialog->Label(-width => 3, -text => "von ")->grid(-row => $row, -column => 2, -sticky => 'e', -ipadx => 35);
		my $benniesmax_entry = $edit_dialog->Entry(-width => 2, -textvariable => \$avatar->{benniesmax})->grid(-row => $row, -column => 2, -sticky => 'e');
		
		# Heiltränke
		my $heiltrank_label = $edit_dialog->Label(-text => "Tägliche Heiltränke")->grid(-row => $row, -column => 3, -sticky => 'w');
		$heiltrank_entry = $edit_dialog->Label(-text => $avatar->{heiltrank})->grid(-row => $row, -column => 3, -sticky => 'e');
		$row++;

		# Skills
		my $skill_label = $edit_dialog->Label(-text => "Fertigkeiten")->grid(-row => $row + 1, -column => 0, -columnspan => 2);
		
		# Machtpunkte
		my $mp_label = $edit_dialog->Label(-text => "Machtpunkte")->grid(-row => $row, -column => 0, -sticky => 'w');
		my $mp_entry = $edit_dialog->Entry(-textvariable => $avatar->{mp})->grid(-row => $row, -column => 1, -sticky => 'w');

		# Wunden
		my $wunden_label = $edit_dialog->Label(-text => "Wunden")->grid(-row => $row, -column => 2, -sticky => 'w');
		my $wunden_entry = $edit_dialog->Entry(-width => 2, -textvariable => \$avatar->{wunden})->grid(-row => $row, -column => 2, -sticky => 'n');
		my $wundenmax_label = $edit_dialog->Label(-width => 3, -text => "von ")->grid(-row => $row, -column => 2, -sticky => 'e', -ipadx => 35);
		my $wundenmax_entry = $edit_dialog->Entry(-width => 2, -textvariable => \$avatar->{wundenmax})->grid(-row => $row, -column => 2, -sticky => 'e');
		
		# Machttränke
		my $machttrank_label = $edit_dialog->Label(-text => 'Tägliche Machttränke')->grid(-row => $row, -column => 3, -sticky => 'w');
		$machttrank_entry = $edit_dialog->Label(-text => $avatar->{machttrank})->grid(-row => $row, -column => 3, -sticky => 'e');
		$row += 2;

		foreach my $skill (sort keys %avatar_skills_values) {
			$skills_fields{$skill}{label} = $edit_dialog->Label(-text => $skill)->grid(-row => $row, -column => 0, -sticky => 'w');
			$skills_fields{$skill}{skillmod_label} = $edit_dialog->Label(-width => 3, -text => "Mod")->grid(-row => $row, -column => 0, -sticky => 'n');
			$skills_fields{$skill}{skillmod_entry} = $edit_dialog->Entry(-width => 3, -textvariable => \$skill_mods{$skill}, -validate => 'key', -validatecommand => sub {
				my $new_value = shift;
				return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
				return 0;
			})->grid(-row => $row, -column => 0, -sticky => 'e');

			$skills_fields{$skill}{entry} = $edit_dialog->Label(-text => "W$avatar_skills_values{$skill}")->grid(-row => $row, -column => 1, -sticky => 'w');

			$skills_fields{$skill}{skillmod_entry}->bind('<KeyRelease>', sub {
				my $mod_value = $skills_fields{$skill}{skillmod_entry}->get();
				if ($mod_value =~ /^[\+-]?\d+$/) {
					update_display_avatar($avatar_skills_values{$skill}, $mod_value, $skills_fields{$skill}{entry}, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
					$skill_mods{$skill} = $mod_value;
				}
				if($skill eq "Nahkampf")
				{
					update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
				}
				elsif($skill eq "Konstitution")
				{
					update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
				}
			});

			my $increase_button = $edit_dialog->Button(
				-text => "+",
				-command => sub {
					if($sp_entry->cget('-text') == 0)
					{
						$edit_dialog->messageBox(
						-type    => 'Ok',
						-icon    => 'error',
						-title   => 'Keine Fertigkeitspunkte mehr',
						-message => "Keine Fertigkeitspunkte mehr zum Verteilen!"
						);
					}
					else
					{
						my $current_value = $avatar_skills_values{$skill};
						if ($current_value =~ /^(\d+)$/) {
							my $number = $1;
							if($number == 0) {
								$avatar_skills_values{$skill} = 4;
								$sp_entry->configure(-text => $sp_entry->cget('-text') - 1);
							}
							elsif ($number < 12) {
								if($number > 6 && $sp_entry->cget('-text') < 2)
								{
									$edit_dialog->messageBox(
									-type    => 'Ok',
									-icon    => 'error',
									-title   => 'Nicht genug Fertigkeitspunkte',
									-message => "Fertigkeiten über W8 kosten 2 Punkte, es ist aber nur noch einer da!"
									);
								}
								else
								{
									$number+=2;
									$avatar_skills_values{$skill} = $number;
									if($number > 8)
									{
										$sp_entry->configure(-text => $sp_entry->cget('-text') - 2);
									}
									else
									{
										$sp_entry->configure(-text => $sp_entry->cget('-text') - 1);
									}
								}
							} elsif ($number == 12) {
								if($sp_entry->cget('-text') < 2)
								{
									$edit_dialog->messageBox(
									-type    => 'Ok',
									-icon    => 'error',
									-title   => 'Nicht genug Fertigkeitspunkte',
									-message => "Fertigkeiten über W8 kosten 2 Punkte, es ist aber nur noch einer da!"
									);
								}
								else
								{
									$avatar_skills_values{$skill} = "12+1";
									$sp_entry->configure(-text => $sp_entry->cget('-text') - 2);
								}
							}
						} elsif ($current_value =~ /^12\+(\d+)$/) {
							my $number = $1;
							if($sp_entry->cget('-text') < 2)
							{
								$edit_dialog->messageBox(
								-type    => 'Ok',
								-icon    => 'error',
								-title   => 'Nicht genug Fertigkeitspunkte',
								-message => "Fertigkeiten über W8 kosten 2 Punkte, es ist aber nur noch einer da!"
								);
							}
							else
							{
								$sp_entry->configure(-text => $sp_entry->cget('-text') - 2);
								$number++;
								$avatar_skills_values{$skill} = "12+$number";
							}
						}
						update_display_avatar($avatar_skills_values{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
						if($skill eq "Nahkampf")
						{
							update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
						}
						elsif($skill eq "Konstitution")
						{
							update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
						}
					}
				}
			)->grid(-row => $row, -column => 1, -sticky => 'n', -ipadx=> 8);

			my $decrease_button = $edit_dialog->Button(
				-text => "-",
				-command => sub {
					my $current_value = $avatar_skills_values{$skill};
					if ($current_value =~ /^(\d+)$/) {
						my $number = $1;
						if($number == 4) {
							$sp_entry->configure(-text => $sp_entry->cget('-text') + 1);
							$avatar_skills_values{$skill} = 0;
						}
						elsif ($number > 0) {
							$number-=2;
							$avatar_skills_values{$skill} = $number;
							if($number > 6)
							{
								$sp_entry->configure(-text => $sp_entry->cget('-text') + 2);
							}
							else
							{
								$sp_entry->configure(-text => $sp_entry->cget('-text') + 1);
							}
						}
					} elsif ($current_value =~ /^12\+(\d+)$/) {
						my $number = $1;
						$sp_entry->configure(-text => $sp_entry->cget('-text') + 2);
						if ($number > 1) {
							$number--;
							$avatar_skills_values{$skill} = "12+$number";
						} else {
							$avatar_skills_values{$skill} = 12;
						}
					}
					update_display_avatar($avatar_skills_values{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
					if($skill eq "Nahkampf")
					{
						update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{Nahkampf}, $skill_mods{Nahkampf});
					}
					elsif($skill eq "Konstitution")
					{
						update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
					}
				}
			)->grid(-row => $row, -column => 1, -sticky => 'e', -ipadx=> 8);
			update_display_avatar($avatar_skills_values{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods);
			if($skill eq "Nahkampf")
			{
				update_parade_avatar($char_skills, $char_skill_mods, $char_attributes, $char_attr_mods, $parade_basis, $parademod_entry, $paradegs_entry, $avatar_skills_values{$skill}, $skill_mods{$skill});
			}
			elsif($skill eq "Konstitution")
			{
				update_robust_avatar($avatar_skills_values{Konstitution}, $skill_mods{Konstitution}, $robust_basis, $robustmod_entry, $robustgs_entry);
			}
			$row++;
		}

		# Abgeleitete Werte
		my $abglw_label = $edit_dialog->Label(-text => "Abgeleitete Werte")->grid(-row => 5, -column => 2, -columnspan => 4);
		my $bewegung_label = $edit_dialog->Label(-text => "Bewegung")->grid(-row => 6, -column => 2, -sticky => 'w');
		my $bewegung_basis = $edit_dialog->Label(-width => 3, -text => 6)->grid(-row => 6, -column => 2, -sticky => 'n');
		my $bewegungmod_label = $edit_dialog->Label(-width => 3, -text => "Mod")->grid(-row => 6, -column => 2, -sticky => 'e', -ipadx => 10);
		my $bewegungmod_entry = $edit_dialog->Entry(-width => 3, -textvariable => \$avatar->{bewegungmod}, -validate => 'key', -validatecommand => sub {
			my $new_value = shift;
			return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
			return 0;
		})->grid(-row => 6, -column => 3, -sticky => 'w');
		my $bewegungges_label = $edit_dialog->Label(-text => "Gesamt")->grid(-row => 6, -column => 3, -sticky => 'n');
		my $bewegunggs_entry = $edit_dialog->Label(-width => 3, -text => $bewegung_basis->cget('-text') + $avatar->{bewegungmod} . '"')->grid(-row => 6, -column => 3, -sticky => 'e');

		$bewegungmod_entry->bind('<KeyRelease>', sub {
			my $mod_value = $bewegungmod_entry->get();
			if ($mod_value =~ /^[\+-]?\d+$/) {
				$bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') + $mod_value . '"');
			} elsif ($mod_value =~ /^[\+-]?\d*$/) {
				$bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') . '"');
			} else {
				$edit_dialog->messageBox(
					-type    => 'Ok',
					-icon    => 'error',
					-title   => 'Bewegungs-Mod fehlerhaft',
					-message => "Bitte den Wert im Mod-Feld bei Bewegung prüfen.\nSetze den Gesamt-Wert auf den Basis-Wert."
				);
				$bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') . '"');
			}
		});

		# Inventarverwaltung
		my $inventar_label = $edit_dialog->Label(-text => "Inventarverwaltung")->grid(-row => 9, -column => 2, -columnspan => 2);

		# Charakterbild
		my $dirname = get_script_dir();

		unless (-e "$dirname/avatar.gif") {
			die "Fehler: Bilddatei avatar.gif konnte nicht gefunden werden.\n";
		}

		my $image = $edit_dialog->Photo(-file => "$dirname/avatar.gif");
		my $canvas = $edit_dialog->Canvas(
			-width  => 257,
			-height => 257
		)->grid(
			-row      => 10,       # Startzeile
			-column   => 2,       # Spalte rechts neben den anderen Widgets
			-rowspan  => 10,      # Erstreckt sich über 10 Zeilen
			-columnspan  => 2,      # Erstreckt sich über 10 Zeilen
			-sticky   => 'nsew'   # Füllt den zugewiesenen Bereich aus
		);
		$canvas->createImage(0, 0, -image => $image, -anchor => 'nw');

		my %waffenwerte = %{$avatar->{waffen}};
		my %panzerwerte = %{$avatar->{panzer}};

		# Definieren der Bereiche für Körperteile (angepasste Koordinaten)
		my $head_coords = [114, 11, 144, 44];
		my $body_coords = [104, 45, 153, 123];
		my $right_arm_coords = [54, 32, 103, 63];
		my $left_arm_coords = [154, 32, 203, 60];
		my $beine_coords = [97, 124, 162, 226];
		my $left_hand_coords = [204, 32, 237, 60];
		my $right_hand_coords = [21, 32, 53, 60];

		# Erstellen der Klickbereiche
		create_clickable_area($head_coords, 'head', $canvas);
		create_clickable_area($body_coords, 'body', $canvas);
		create_clickable_area($left_arm_coords, 'left_arm', $canvas);
		create_clickable_area($right_arm_coords, 'right_arm', $canvas);
		create_clickable_area($beine_coords, 'beine', $canvas);
		create_clickable_area($left_hand_coords, 'left_hand', $canvas);
		create_clickable_area($right_hand_coords, 'right_hand', $canvas);

		# Ereignishandler für Klicks auf die Körperteile
		$row++;
		my $kopf_label = $edit_dialog->Label(-text => "Kopf")->grid(-row => 11, -column => 3, -sticky => 'e');
		my $kopf_entry = $edit_dialog->Label(-text => "$panzerwerte{Kopf}{name}, P $panzerwerte{Kopf}{panzerung}")->grid(-row => 11, -column => 4, -sticky => 'w', -columnspan => 5);
		my $arme_label = $edit_dialog->Label(-text => "Arme")->grid(-row => 12, -column => 3, -sticky => 'e');
		my $arme_entry = $edit_dialog->Label(-text => "$panzerwerte{Arme}{name}, P $panzerwerte{Arme}{panzerung}")->grid(-row => 12, -column => 4, -sticky => 'w', -columnspan => 5);
		my $lhand_label = $edit_dialog->Label(-text => "Linke Hand")->grid(-row => 13, -column => 3, -sticky => 'e');
		my $lhand_entry = $edit_dialog->Label(-text => "$waffenwerte{'linke Hand'}{name}")->grid(-row => 13, -column => 4, -sticky => 'w', -columnspan => 5);
		my $rhand_label = $edit_dialog->Label(-text => "Rechte Hand")->grid(-row => 14, -column => 3, -sticky => 'e');
		my $rhand_entry = $edit_dialog->Label(-text => "$waffenwerte{'rechte Hand'}{name}")->grid(-row => 14, -column => 4, -sticky => 'w', -columnspan => 5);
		my $torso_label = $edit_dialog->Label(-text => "Torso")->grid(-row => 15, -column => 3, -sticky => 'e');
		my $torso_entry = $edit_dialog->Label(-text => "$panzerwerte{Torso}{name}, P $panzerwerte{Torso}{panzerung}")->grid(-row => 15, -column => 4, -sticky => 'w', -columnspan => 5);
		my $beine_label = $edit_dialog->Label(-text => "Beine")->grid(-row => 16, -column => 3, -sticky => 'e');
		my $beine_entry = $edit_dialog->Label(-text => "$panzerwerte{Beine}{name}, P $panzerwerte{Beine}{panzerung}")->grid(-row => 16, -column => 4, -sticky => 'w', -columnspan => 5);
		$canvas->bind('head', '<Button-1>', sub { update_item_label($edit_dialog, 'Kopf', $kopf_entry, \%panzerwerte) });
		$canvas->bind('body', '<Button-1>', sub { update_item_label($edit_dialog, 'Torso', $torso_entry, \%panzerwerte) });
		$canvas->bind('left_arm', '<Button-1>', sub { update_item_label($edit_dialog, 'Arme', $arme_entry, \%panzerwerte) });
		$canvas->bind('right_arm', '<Button-1>', sub { update_item_label($edit_dialog, 'Arme', $arme_entry, \%panzerwerte) });
		$canvas->bind('beine', '<Button-1>', sub { update_item_label($edit_dialog, 'Beine', $beine_entry, \%panzerwerte) });
		$canvas->bind('left_hand', '<Button-1>', sub { update_weapon_label($edit_dialog, 'linke Hand', $lhand_entry, \%waffenwerte) });
		$canvas->bind('right_hand', '<Button-1>', sub { update_weapon_label($edit_dialog, 'rechte Hand', $rhand_entry, \%waffenwerte) });
		
		my $notizen_button = $edit_dialog->Button(-text => "Notizen", -command => sub {open_notizen_window($avatar, $edit_dialog)})->grid(-row => 18, -column => 4, -sticky => 'w', -columnspan => 5);

		my %wissen_skills = %{$avatar->{wissen}};
		my $verstand_benutzt = -1;
		my $wissen_button = $edit_dialog->Button(
			-text => "Wissensfertigkeiten",
			-command => sub {
				manage_wissen_skills("Fertigkeitspunkte", $edit_dialog, \%wissen_skills, \$verstand_benutzt, -1, $sp_entry);
			}
		)->grid(-row => $row - 3, -column => 2);

		# Vermögen
		my $vermoegen_label  = $edit_dialog->Label(-text => "Vermögen")->grid(-row => $row - 2, -column => 2);
		my $vermoegen_entry = $edit_dialog->Entry(-textvariable => \$avatar->{vermoegen})->grid(-row => $row - 2, -column => 3, -sticky => 'w');

		# Inventarslots
		my $inventarslots_label  = $edit_dialog->Label(-text => "Inventarslots")->grid(-row => $row - 1, -column => 2);
		$inventarslots_entry = $edit_dialog->Label(-text => $avatar->{inventarslots})->grid(-row => $row - 1, -column => 3, -sticky => 'w');

		# Talents
		my $talent_frame = create_talent_frame($sp_entry, $edit_dialog, $row, $avatar->{talents});

		# Gegenstände
		my $items_label = $edit_dialog->Label(-text => "Ausrüstung")->grid(-row => $row, -column => 2);
		$row++;
		my $items_listbox = $edit_dialog->Scrolled(
			'Listbox',
			-scrollbars => 'se',  # Vertical scrollbar
			-height     => 5,
			-width      => 30,
		)->grid(-row => $row, -column => 2, -sticky => 'w');
		$items_listbox->Subwidget('listbox')->bind('<Enter>', sub{$items_listbox->Subwidget('listbox')->focus()});
		$items_listbox->Subwidget('listbox')->bind('<Leave>', sub {$edit_dialog->focus();});

		my $items_button_frame = $edit_dialog->Frame()->grid(-row => $row, -column => 3, -sticky => 'w');
		$items_button_frame->Button(
			-text => "+",
			-command => sub { add_items_item($edit_dialog, $items_listbox, $inventarslots_entry->cget(-text), 'Gegenstand') }
		)->pack(-side => 'top');
		$items_button_frame->Button(
			-text => "-",
			-command => sub { delete_items_item($edit_dialog, $items_listbox) }
		)->pack(-side => 'top');

		# Populate Items Listbox
		foreach my $item (@{$avatar->{items}}) {
			$items_listbox->insert('end', $item);
		}
		
		$row += 2;
		
		# Handicaps
		my $handicap_frame = create_handicap_frame($sp_entry, $edit_dialog, $row, $avatar->{handicaps});
		
		# Mächte
		my $maechte_label = $edit_dialog->Label(-text => "Mächte")->grid(-row => $row, -column => 2);
		$row++;
		my $maechte_listbox = $edit_dialog->Scrolled(
			'Listbox',
			-scrollbars => 'se',  # Vertical scrollbar
			-height     => 5,
			-width      => 30,
		)->grid(-row => $row, -column => 2, -sticky => 'w');
		$maechte_listbox->Subwidget('listbox')->bind('<Enter>', sub{$maechte_listbox->Subwidget('listbox')->focus()});
		$maechte_listbox->Subwidget('listbox')->bind('<Leave>', sub {$edit_dialog->focus();});

		my $maechte_button_frame = $edit_dialog->Frame()->grid(-row => $row, -column => 3, -sticky => 'w');
		$maechte_button_frame->Button(
			-text => "+",
			-command => sub { add_items_item($edit_dialog, $maechte_listbox, 0, 'Macht') }
		)->pack(-side => 'top');
		$maechte_button_frame->Button(
			-text => "-",
			-command => sub { delete_items_item($edit_dialog, $maechte_listbox) }
		)->pack(-side => 'top');
		
		# Populate Mächte Listbox
		foreach my $macht (@{$avatar->{maechte}}) {
			$maechte_listbox->insert('end', $macht);
		}

		$row += 2;
		# Save Button
		$edit_dialog->Button(
			-text    => "Speichern",
			-command => sub {
				$avatar->{name} = $name_entry->get();
				$avatar->{game} = $game_entry->get();
				$avatar->{description} = $description_entry->get();
				$avatar->{gilden} = $gilden_entry->get();
				$avatar->{xp} = $xp_entry->cget('-text');
				$avatar->{vermoegen} = $vermoegen_entry->get();
				$avatar->{rank} = $rank_entry->cget('-text');
				$avatar->{level} = $level_entry->cget('-text');
				$avatar->{bennies} = $bennies_entry->get();
				$avatar->{benniesmax} = $benniesmax_entry->get();
				$avatar->{heiltrank} = $heiltrank_entry->cget('-text');
				$avatar->{machttrank} = $machttrank_entry->cget('-text');
				$avatar->{mp} = $mp_entry->get();
				$avatar->{wunden} = $wunden_entry->get();
				$avatar->{wundenmax} = $wundenmax_entry->get();
				$avatar->{bewegungmod} = $bewegungmod_entry->get();
				$avatar->{inventarslots} = $inventarslots_entry->cget('-text');
				$avatar->{steigerungspunkte} = $sp_entry->cget('-text');
				$avatar->{parademod} = $parademod_entry->get();
				$avatar->{robustmod} = $robustmod_entry->get();
				$avatar->{talents} = [$talent_frame->get(0, 'end')];
				$avatar->{handicaps} = [$handicap_frame->get(0, 'end')];
				$avatar->{panzer} = { %panzerwerte };
				$avatar->{wissen} = { %wissen_skills };
				$avatar->{waffen} = { %waffenwerte };
				$avatar->{items} = [$items_listbox->get(0, 'end')];
				$avatar->{maechte} = [$maechte_listbox->get(0, 'end')];
				$avatar->{skills} = { %avatar_skills_values };
				$avatar->{skill_mods} = { %skill_mods };
				$avatar_listbox->delete($index);
				$avatar_listbox->insert($index, $avatar->{name} . ' (' . $avatar->{game} . ')');
				$parent_dialog->focus();
				$edit_avatar->destroy();
			}
		)->grid(-row => $row, -column => 1, -sticky => 'w');
	}
}

sub delete_avatar {
    my ($parent_dialog, $avatars_ref, $avatar_listbox) = @_;

    my $selected = $avatar_listbox->curselection();
    unless(defined $selected)
	{
		$parent_dialog->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Avatar wählen',
            -message => "Bitte einen Avatar auswählen."
        );
		return;
	}
	
    my $index = $selected->[0];
	if($index == 0)
	{
		$parent_dialog->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Löschen unmöglich',
            -message => "Der Uniworld-Haupt-Avatar kann nicht gelöscht werden."
        );
	}
	else
	{
		my $response = $parent_dialog->messageBox(
			-type    => 'YesNo',
			-icon    => 'question',
			-title   => 'Avatar löschen',
			-message => "Möchten Sie den Avatar wirklich löschen?"
		);

		if (defined $response && $response eq 'Yes') {
			splice @$avatars_ref, $index, 1;
			$avatar_listbox->delete($index);
		}
	}
}

sub create_talent_frame {
    my ($talentpunkt_entry, $dialog, $row, $talents) = @_;
    $talents //= [];

    my $talent_label = $dialog->Label(-text => "Talente")->grid(-row => $row, -column => 0, -columnspan => 2);
    $row++;

    my $talent_frame = $dialog->Frame()->grid(-row => $row, -column => 0, -columnspan => 2);
    my $talent_listbox = $talent_frame->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->pack(-side => 'left', -fill => 'both', -expand => 1);
    $talent_listbox->Subwidget('listbox')->bind('<Enter>', sub{$talent_listbox->Subwidget('listbox')->focus()});
    $talent_listbox->Subwidget('listbox')->bind('<Leave>', sub {$dialog->focus();});

    my $talent_button_frame = $talent_frame->Frame()->pack(-side => 'right', -fill => 'y');
    $talent_button_frame->Button(
        -text => "+",
        -command => sub { add_talent($talentpunkt_entry, $dialog, $talent_listbox) }
    )->pack(-side => 'top');

    $talent_button_frame->Button(
        -text => "-",
        -command => sub { delete_talent($talentpunkt_entry, $dialog, $talent_listbox) }
    )->pack(-side => 'top');

    # Populate Talents Listbox
    foreach my $talent (@$talents) {
        $talent_listbox->insert('end', $talent);
    }

    return $talent_listbox;
}

sub add_talent {
    my ($talentpunkt_entry, $dialog, $talent_listbox) = @_;
	
	if($talentpunkt_entry->cget('-text') < 2)
	{
		$dialog->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Nicht genug Punkte übrig',
            -message => "Nicht genug Punkte übrig."
        );
	}
	else
	{
		my $talent_entry = $dialog->DialogBox(
        -title   => "Talent hinzufügen",
        -buttons => ["OK", "Abbrechen"],
		);
		$talent_entry->geometry("250x75");
		$talent_entry->add('Label', -text => "Talent:")->pack();
		my $talent_input = $talent_entry->add('Entry')->pack();
		my $response = $talent_entry->Show();
		if (defined $response && $response eq "OK" && $talent_input->get() ne "")
		{
			$talentpunkt_entry->configure(-text => $talentpunkt_entry->cget('-text') - 2);
			my $new_talent = $talent_input->get();

			# Füge den neuen Eintrag zur Listbox hinzu
			$talent_listbox->insert('end', $new_talent);

			# Hole alle Einträge aus der Listbox
			my @talents = $talent_listbox->get(0, 'end');

			# Sortiere die Einträge alphabetisch
			@talents = sort @talents;

			# Aktualisiere die Listbox
			$talent_listbox->delete(0, 'end');
			foreach my $talent (@talents)
			{
				$talent_listbox->insert('end', $talent);
			}
			$dialog->focus();  # Set focus back to dialog
		}
	}

}

sub delete_talent {
    my ($talentpunkt_entry, $dialog, $talent_listbox) = @_;

    my $selected = $talent_listbox->curselection();
    if (defined $selected && @$selected) {
        $talent_listbox->delete($selected->[0]);
		$talentpunkt_entry->configure(-text => $talentpunkt_entry->cget('-text') + 2);
    } else {
        # Optional: Fehlermeldung anzeigen
        $dialog->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Kein Talent ausgewählt',
            -message => "Bitte wählen Sie ein Talent aus, das gelöscht werden soll."
        );
    }
    $dialog->focus();  # Set focus back to dialog
}

sub create_handicap_frame {
    my ($talentpunkt_entry, $dialog, $row, $handicaps) = @_;
    $handicaps //= [];

    my $handicap_label = $dialog->Label(-text => "Handicaps")->grid(-row => $row, -column => 0, -columnspan => 2);
    $row++;

    my $handicap_frame = $dialog->Frame()->grid(-row => $row, -column => 0, -columnspan => 2);
    my $handicap_listbox = $handicap_frame->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->pack(-side => 'left', -fill => 'both', -expand => 1);
    $handicap_listbox->Subwidget('listbox')->bind('<Enter>', sub{$handicap_listbox->Subwidget('listbox')->focus()});
    $handicap_listbox->Subwidget('listbox')->bind('<Leave>', sub {$dialog->focus();});

    my $handicap_button_frame = $handicap_frame->Frame()->pack(-side => 'right', -fill => 'y');
    $handicap_button_frame->Button(
        -text => "+",
        -command => sub { add_handicap($talentpunkt_entry, $dialog, $handicap_listbox) }
    )->pack(-side => 'top');

    $handicap_button_frame->Button(
        -text => "-",
        -command => sub { delete_handicap($talentpunkt_entry, $dialog, $handicap_listbox) }
    )->pack(-side => 'top');

    # Populate Handicaps Listbox
    foreach my $handicap (@$handicaps) {
        $handicap_listbox->insert('end', $handicap);
    }

    return $handicap_listbox;
}

sub add_handicap {
    my ($talentpunkt_entry, $dialog, $handicap_listbox) = @_;

    my $handicap_entry = $dialog->DialogBox(
        -title   => "Handicap hinzufügen",
        -buttons => ["OK", "Abbrechen"],
    );
    $handicap_entry->geometry("300x150");
    $handicap_entry->add('Label', -text => "Handicap:")->pack();
    my $handicap_input = $handicap_entry->add('Entry')->pack();

    # Radio buttons for handicap type
    my $handicap_type = 'Leicht';  # Default value
    $handicap_entry->add('Label', -text => "Handicap-Typ:")->pack();
    my $light_radio = $handicap_entry->add('Radiobutton',
        -text     => 'Leicht',
        -variable => \$handicap_type,
        -value    => 'Leicht',
    )->pack();
    my $heavy_radio = $handicap_entry->add('Radiobutton',
        -text     => 'Schwer',
        -variable => \$handicap_type,
        -value    => 'Schwer',
    )->pack();

    my $response = $handicap_entry->Show();
    if (defined $response && $response eq "OK" && $handicap_input->get() ne "") {
        my $new_handicap = $handicap_input->get() . " ($handicap_type)";
		if($handicap_type eq 'Leicht')
		{
			$talentpunkt_entry->configure(-text => $talentpunkt_entry->cget('-text') + 1);
		}
		else
		{
			$talentpunkt_entry->configure(-text => $talentpunkt_entry->cget('-text') + 2);
		}

        # Füge den neuen Eintrag zur Listbox hinzu
        $handicap_listbox->insert('end', $new_handicap);

        # Hole alle Einträge aus der Listbox
        my @handicaps = $handicap_listbox->get(0, 'end');

        # Sortiere die Einträge alphabetisch
        @handicaps = sort @handicaps;

        # Aktualisiere die Listbox
        $handicap_listbox->delete(0, 'end');
        foreach my $handicap (@handicaps) {
            $handicap_listbox->insert('end', $handicap);
        }

        $dialog->focus();  # Set focus back to dialog
    }
}

sub delete_handicap {
    my ($talentpunkt_entry, $dialog, $handicap_listbox) = @_;

    my $selected = $handicap_listbox->curselection();
    if (defined $selected && @$selected)
	{
		if($handicap_listbox->get($selected) =~ /\(Leicht\)$/)
		{
			if($talentpunkt_entry->cget('-text') > 0)
			{
				$handicap_listbox->delete($selected->[0]);
				$talentpunkt_entry->configure(-text => $talentpunkt_entry->cget('-text') - 1);
			}
			else
			{
				$dialog->messageBox(
				-type    => 'Ok',
				-icon    => 'info',
				-title   => 'Punkte verbraucht',
				-message => "Es sind alle Punkte verbraucht. Handicap kann nicht entfernt werden."
				);
			}
		}
		else
		{
			if($talentpunkt_entry->cget('-text') > 1)
			{
				$handicap_listbox->delete($selected->[0]);
				$talentpunkt_entry->configure(-text => $talentpunkt_entry->cget('-text') - 2);
			}
			else
			{
				$dialog->messageBox(
				-type    => 'Ok',
				-icon    => 'info',
				-title   => 'Punkte verbraucht',
				-message => "Es sind alle Punkte verbraucht. Handicap kann nicht entfernt werden."
				);
			}
		}
		
        
    } else {
        # Optional: Fehlermeldung anzeigen
        $dialog->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Kein Handicap ausgewählt',
            -message => "Bitte wählen Sie ein Handicap aus, das gelöscht werden soll."
        );
    }
    $dialog->focus();  # Set focus back to dialog
}

sub create_character {
    my $add_char = $mw->Toplevel();
	$add_char->geometry("470x150");  # Set window size
	focus_dialog($add_char, "Neuer Charakter - Grunddaten", $mw);

	my $scrolled_area = $add_char->Scrolled(
        'Frame',
        -scrollbars => 'osoe'
    )->pack(-fill => 'both', -expand => 1);
	my $pre_dialog = $scrolled_area->Subwidget('scrolled');

    # Variablen für Eingabefelder
    my ($name, $av_name, $attr_points, $skill_points) = ("", "", 5, 9);

    # GUI-Elemente
    $pre_dialog->Label(-text => "Charaktername:")->grid(-row => 0, -column => 0, -sticky => 'w');
    my $name_entry = $pre_dialog->Entry(-textvariable => \$name)->grid(-row => 0, -column => 1);
	
	$pre_dialog->Label(-text => "Haupt-Avatar-Name:")->grid(-row => 1, -column => 0, -sticky => 'w');
    my $avname_entry = $pre_dialog->Entry(-textvariable => \$av_name)->grid(-row => 1, -column => 1);

    $pre_dialog->Label(-text => "Attributspunkte (Standard 5):")->grid(-row => 2, -column => 0, -sticky => 'w');
    my $attr_entry = $pre_dialog->Entry(
        -textvariable => \$attr_points,
        -validate => 'key',
        -validatecommand => sub { $_[0] =~ /^\d+$/ }
    )->grid(-row => 2, -column => 1);
	
	$pre_dialog->Label(-text => "Fertigkeitspunkte (Standard 9):")->grid(-row => 3, -column => 0, -sticky => 'w');
    my $skill_entry = $pre_dialog->Entry(
        -textvariable => \$skill_points,
        -validate => 'key',
        -validatecommand => sub { $_[0] =~ /^\d+$/ }
    )->grid(-row => 3, -column => 1);

    # Bestätigungs-Button
    $pre_dialog->Button(
        -text => "Weiter",
        -command => sub {
            # Validierung der Eingaben
            unless ($name && $av_name && $attr_points && $skill_points) {
                $pre_dialog->messageBox(-type => 'Ok', -icon => 'error', 
                    -title => 'Fehler', -message => "Bitte alle Felder ausfüllen!");
                return;
            }
            $add_char->destroy();
            # Haupt-Charaktererstellung aufrufen
            main_character_creation($name, $av_name, $attr_points, $skill_points);
        }
    )->grid(-row => 4, -columnspan => 2);

    # Abbrechen-Button
    $pre_dialog->Button(
        -text => "Abbrechen",
        -command => sub { $add_char->destroy }
    )->grid(-row => 5, -columnspan => 2);
}

sub main_character_creation {
	
	my ($name, $av_name, $attr_points, $skill_points) = @_;
    
    my $add_char = $mw->Toplevel();
	focus_dialog($add_char, "Neuen Charakter erstellen", $mw);
    $add_char->geometry("950x950");  # Width x Height in pixels
	
	my $scrolled_area = $add_char->Scrolled(
        'Frame',
        -scrollbars => 'osoe' # Scrollbars nur rechts/unten bei Bedarf
    )->pack(-fill => 'both', -expand => 1); # Füllt das gesamte Dialogfenster

    my $dialog = $scrolled_area->Subwidget('scrolled');
	my $balloon = $dialog->Balloon();
	my $verstand_benutzt = 0;
    my $row = 0;
	my $spacer = $dialog->Label(-text => "", -width => 42)->grid(-row => 0, -column => 0);
    # Name
    my $name_label = $dialog->Label(-text => "Name")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $name_entry = $dialog->Entry(-text => $name)->grid(-row => $row, -column => 1, -sticky => 'w');

    # XP
    my $xp_label  = $dialog->Label(-text => "Erfahrungspunkte")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $xp_entry = $dialog->Label(-width => 3, -text => 0)->grid(-row => $row, -column => 2, -sticky => 'n');

	# Attributspunkte über
	my $attrpunkt_label  = $dialog->Label(-text => "Attributspunkte über")->grid(-row => $row, -column => 3, -sticky => 'w');
    my $attrpunkt_entry = $dialog->Label(-text => $attr_points)->grid(-row => $row, -column => 3, -sticky => 'e');
	$row++;

    # Wohnort
    my $location_label = $dialog->Label(-text => "Wohnort")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $location_entry = $dialog->Entry()->grid(-row => $row, -column => 1, -sticky => 'w');

    # Rank
    my $rank_label  = $dialog->Label(-text => "Rang")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $rank_entry = $dialog->Label(-width => 11, -text => 'Anfänger')->grid(-row => $row, -column => 2, -sticky => 'n');
	
	# Fertigkeitspunkte über
	my $skillpunkt_label  = $dialog->Label(-text => "Fertigkeitspunkte über")->grid(-row => $row, -column => 3, -sticky => 'w');
    my $skillpunkt_entry = $dialog->Label(-text => $skill_points)->grid(-row => $row, -column => 3, -sticky => 'e');
    $row++;

    # Beschreibung
    my $description_label = $dialog->Label(-text => "Beschreibung")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $description_entry = $dialog->Entry()->grid(-row => $row, -column => 1, -sticky => 'w');

    # Bennies
    my $bennies_label = $dialog->Label(-text => "Bennies")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $bennies_entry = $dialog->Entry(-width => 2, -textvariable => 3)->grid(-row => $row, -column => 2, -sticky => 'n');
    my $benniesmax_label = $dialog->Label(-width => 3, -text => "von ")->grid(-row => $row, -column => 2, -sticky => 'e', -ipadx=> 35);
    my $benniesmax_entry = $dialog->Entry(-width => 2, -textvariable => 3)->grid(-row => $row, -column => 2, -sticky => 'e',);

	# Talentpunkte über
	my $talentpunkt_label  = $dialog->Label(-text => "Talentpunkte über")->grid(-row => $row, -column => 3, -sticky => 'w');
    my $talentpunkt_entry = $dialog->Label(-text => 0)->grid(-row => $row, -column => 3, -sticky => 'e');
    $row++;
	
	# Beschreibung
    my $alter_label = $dialog->Label(-text => "Alter")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $alter_entry = $dialog->Entry()->grid(-row => $row, -column => 1, -sticky => 'w');

    # Wunden
    my $wunden_label = $dialog->Label(-text => "Wunden")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $wunden_entry = $dialog->Entry(-width => 2, -textvariable => 0)->grid(-row => $row, -column => 2, -sticky => 'n');
    my $wundenmax_label = $dialog->Label(-width => 3, -text => "von ")->grid(-row => $row, -column => 2, -sticky => 'e', -ipadx=> 35);
    my $wundenmax_entry = $dialog->Entry(-width => 2, -textvariable => 4)->grid(-row => $row, -column => 2, -sticky => 'e',);
    $row+=2;
	
	# Online-Zeit
	my $online_basis = $dialog->Label(-width => 3, -text => 2)->grid(-row => 8, -column => 2, -sticky => 'n');
	my $online_label = $dialog->Label(-text => "Online-Zeit")->grid(-row => 8, -column => 2, -sticky => 'w');
    my $onlinemod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => 8, -column => 2, -sticky => 'e', -ipadx=> 10);
    my $onlinemod_entry = $dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 8, -column => 3, -sticky => 'w');
    my $onlineges_label = $dialog->Label(-text => "Gesamt")->grid(-row => 8, -column => 3, -sticky => 'n');
    my $onlinegs_entry = $dialog->Label(-width => 3, -text => $online_basis->cget('-text') . " h")->grid(-row => 8, -column => 3, -sticky => 'e', -ipadx=> 10);
	$balloon->attach($onlinegs_entry, -balloonmsg => $online_basis->cget('-text') . " h ohne Malus, dann bis zu " . ($online_basis->cget('-text') + 2) . " h mit Malus 2, dann bis zu " . ($online_basis->cget('-text') + 4) . " h mit Malus 4, dann Pause benötigt.");

	my %attributes = map { $_ => 4 } @char_attributes;
	my %attr_mods = map { $_ => 0 } @char_attributes;

    $onlinemod_entry->bind('<KeyRelease>', sub {
		update_online($attributes{"Körperliche Verfassung"}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{"Körperliche Verfassung"});

    });

	my %skills_fields = ();
	my %skills = map { $_ => 0 } @char_skills;
	my %skill_mods = map { $_ => 0 } @char_skills;
	my $parade_basis;
	my $parademod_entry;
	my $paradegs_entry;
	my $robustgs_entry;
    my $robust_basis;
    my $robustmod_entry;

	# Attributes
	my $attr_label = $dialog->Label(-text => "Attribute")->grid(-row => 4, -column => 0, -columnspan => 2);
	foreach my $attribute (@char_attributes) {
		my $label = $dialog->Label(-text => $attribute)->grid(-row => $row, -column => 0, -sticky => 'w');
		my $attrmod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => $row, -column => 0, -sticky => 'n');
		my $attremod_entry = $dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
			my $new_value = shift;
			return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
			return 0;
		})->grid(-row => $row, -column => 0, -sticky => 'e');
		my $entry = $dialog->Label(-text => "W4")->grid(-row => $row, -column => 1, -sticky => 'w');

		$attremod_entry->bind('<KeyRelease>', sub {
			my $mod_value = $attremod_entry->get();
			if ($mod_value =~ /^[\+-]?\d+$/) {
				update_display($attributes{$attribute}, $mod_value, $entry);
				$attr_mods{$attribute} = $mod_value;
			}
			if ($attribute eq "Körperliche Verfassung")
			{
				update_online($attributes{$attribute}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{$attribute});
				update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
			}
			elsif($attribute eq "Reaktion")
			{
				update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry);
			}
		});

		my $increase_button = $dialog->Button(
			-text => "+",
			-command => sub {
				if($attrpunkt_entry->cget('-text') == 0)
				{
					$dialog->messageBox(
					-type    => 'Ok',
					-icon    => 'error',
					-title   => 'Keine Attributspunkte mehr',
					-message => "Keine Attributspunkte mehr zum Verteilen!"
					);
				}
				else
				{
					$attrpunkt_entry->configure(-text => $attrpunkt_entry->cget('-text') - 1);
					my $current_value = $attributes{$attribute};
					if ($current_value =~ /^(\d+)$/) {
						my $number = $1;
						if ($number < 12) {
							$number += 2;
							$attributes{$attribute} = $number;
						} elsif ($number == 12) {
							$attributes{$attribute} = "12+1";
						}
					} elsif ($current_value =~ /^12\+(\d+)$/) {
						my $number = $1 + 1;
						$attributes{$attribute} = "12+$number";
					}
					update_display($attributes{$attribute}, $attr_mods{$attribute}, $entry);
					if ($attribute eq "Körperliche Verfassung")
					{
						update_online($attributes{$attribute}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{$attribute});
						update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
					}
					elsif($attribute eq "Reaktion")
					{
						update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry);
					}
				}
			}
		)->grid(-row => $row, -column => 1, -sticky => 'n', -ipadx => 8);

		my $decrease_button = $dialog->Button(
			-text => "-",
			-command => sub
			{
				if($attribute eq 'Verstand')
				{
					if(get_bonus_attr_no_mod($attributes{Verstand}, 0) - $verstand_benutzt > 1)
					{
						my $current_value = $attributes{$attribute};
						if ($current_value =~ /^(\d+)$/)
						{
							my $number = $1;
							if ($number == 4) {
								$dialog->messageBox(
									-type    => 'Ok',
									-icon    => 'info',
									-title   => 'Attribut senken',
									-message => "Attribute können nicht niedriger als W4 sein."
								);
							}
							elsif ($number > 4)
							{
								$attrpunkt_entry->configure(-text => $attrpunkt_entry->cget('-text') + 1);
								$number -= 2;
								$attributes{$attribute} = $number;
							}
						}
						elsif ($current_value =~ /^12\+(\d+)$/)
						{
							my $number = $1;
							$attrpunkt_entry->configure(-text => $attrpunkt_entry->cget('-text') + 1);
							if ($number > 1)
							{
								$number--;
								$attributes{$attribute} = "12+$number";
							}
							else
							{
								$attributes{$attribute} = 12;
							}
						}
						update_display($attributes{$attribute}, $attr_mods{$attribute}, $entry);
					}
					else
					{
						$dialog->messageBox(
								-type    => 'Ok',
								-icon    => 'info',
								-title   => 'Verstand senken',
								-message => "Verstand kann nicht weiter gesenkt werden, da es für Wissensfertigkeiten genutzt wird.\nBitte erst Wissensfertigkeiten senken."
							);
					}
				}
				else
				{
					my $current_value = $attributes{$attribute};
					if ($current_value =~ /^(\d+)$/)
					{
						my $number = $1;
						if ($number == 4) {
							$dialog->messageBox(
								-type    => 'Ok',
								-icon    => 'info',
								-title   => 'Attribut senken',
								-message => "Attribute können nicht niedriger als W4 sein."
							);
						}
						elsif ($number > 4)
						{
							$attrpunkt_entry->configure(-text => $attrpunkt_entry->cget('-text') + 1);
							$number -= 2;
							$attributes{$attribute} = $number;
						}
					}
					elsif ($current_value =~ /^12\+(\d+)$/)
					{
						my $number = $1;
						$attrpunkt_entry->configure(-text => $attrpunkt_entry->cget('-text') + 1);
						if ($number > 1)
						{
							$number--;
							$attributes{$attribute} = "12+$number";
						}
						else
						{
							$attributes{$attribute} = 12;
						}
					}
					update_display($attributes{$attribute}, $attr_mods{$attribute}, $entry);
					if ($attribute eq "Körperliche Verfassung")
					{
						update_online($attributes{$attribute}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{$attribute});
						update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
					}
					elsif($attribute eq "Reaktion")
					{
						update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry);
					}
				}
			}
		)->grid(-row => $row, -column => 1, -sticky => 'e', -ipadx => 8);

		$row++;
	}

    # Abgeleitete Werte
    my $abglw_label = $dialog->Label(-text => "Abgeleitete Werte")->grid(-row => 4, -column => 2, -columnspan => 4);
    $row++;

    my $bewegung_label = $dialog->Label(-text => "Bewegung")->grid(-row => 5, -column => 2, -sticky => 'w');
    my $bewegung_basis = $dialog->Label(-width => 3, -text => 6)->grid(-row => 5, -column => 2, -sticky => 'n');
    my $bewegungmod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => 5, -column => 2, -sticky => 'e', -ipadx=> 10);
    my $bewegungmod_entry = $dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 5, -column => 3, -sticky => 'w');
    my $bewegungges_label = $dialog->Label(-text => "Gesamt")->grid(-row => 5, -column => 3, -sticky => 'n');
    my $bewegunggs_entry = $dialog->Label(-width => 3, -text => $bewegung_basis->cget('-text') . '"')->grid(-row => 5, -column => 3, -sticky => 'e', -ipadx=> 10);

    $bewegungmod_entry->bind('<KeyRelease>', sub {
        my $mod_value = $bewegungmod_entry->get();
        if ($mod_value =~ /^[\+-]?\d+$/)
        {
            $bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') + $mod_value . '"');
        }
        elsif ($mod_value =~ /^[\+-]?\d*$/)
        {
            $bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') . '"');
        }
        else
        {
            $dialog->messageBox(
                -type    => 'Ok',
                -icon    => 'error',
                -title   => 'Bewegungs-Mod fehlerhaft',
                -message => "Bitte den Wert im Mod-Feld bei Bewegung prüfen.\nSetze den Gesamt-Wert auf den Basis-Wert."
            );
            $bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') . '"');
        }
    });

    my $parade_label = $dialog->Label(-text => "Parade")->grid(-row => 6, -column => 2, -sticky => 'w');
    $parade_basis = $dialog->Label(-width => 3, -text => 3)->grid(-row => 6, -column => 2, -sticky => 'n');
    my $parademod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => 6, -column => 2, -sticky => 'e', -ipadx=> 10);
    $parademod_entry = $dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 6, -column => 3, -sticky => 'w');
    my $paradeges_label = $dialog->Label(-text => "Gesamt")->grid(-row => 6, -column => 3, -sticky => 'n');
    $paradegs_entry = $dialog->Label(-width => 3, -text => 3)->grid(-row => 6, -column => 3, -sticky => 'e', -ipadx=> 10);
	$parademod_entry->bind('<KeyRelease>', sub { update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry); });
	
	$balloon->attach($parade_basis, -balloonmsg => "Basis: 2 + ((Kämpfen + Mod) / 2) + ((Reaktion + Mod) / 4) + ((Ausweichen + Mod) / 2), aufgerundet");
	$balloon->attach($paradegs_entry, -balloonmsg => "Gesamt: Basis + Modifikator");

    my $robust_label = $dialog->Label(-text => "Robustheit")->grid(-row => 7, -column => 2, -sticky => 'w');
    $robust_basis = $dialog->Label(-width => 3, -text => 4)->grid(-row => 7, -column => 2, -sticky => 'n');
    my $robustmod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => 7, -column => 2, -sticky => 'e', -ipadx=> 10);
    $robustmod_entry = $dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 7, -column => 3, -sticky => 'w');
    my $robustges_label = $dialog->Label(-text => "Gesamt")->grid(-row => 7, -column => 3, -sticky => 'n');
    $robustgs_entry = $dialog->Label(-width => 3, -text => 4)->grid(-row => 7, -column => 3, -sticky => 'e', -ipadx=> 10);

    $robustmod_entry->bind('<KeyRelease>', sub {
        update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
    });

    # Skills
    my $skill_label = $dialog->Label(-text => "Fertigkeiten")->grid(-row => $row, -column => 0, -columnspan => 2);
	my $inventar_label = $dialog->Label(-text => "Inventarverwaltung")->grid(-row => $row, -column => 3);
	
	# Charakterbild
	my $dirname = get_script_dir();
    unless (-e "$dirname/avatar.gif") {
        die "Fehler: Bilddatei avatar.gif konnte nicht gefunden werden.\n";
    }

    my $image = $dialog->Photo(-file => "$dirname/avatar.gif");
	my $canvas = $dialog->Canvas(
    -width  => 257,
    -height => 257
	)->grid(
    -row      => $row + 1,       # Startzeile
    -column   => 2,       # Spalte rechts neben den anderen Widgets
    -rowspan  => 10,      # Erstreckt sich über 10 Zeilen
	-columnspan  => 2,      # Erstreckt sich über 10 Zeilen
    -sticky   => 'nsew'   # Füllt den zugewiesenen Bereich aus
	);
	$canvas->createImage(0, 0, -image => $image, -anchor => 'nw');
	
	my %waffenwerte = ();
	my %panzerwerte = ();
	
	$panzerwerte{Kopf}{name} = "Mütze";
	$panzerwerte{Kopf}{panzerung} = 0;
	$panzerwerte{Kopf}{kv} = 0;
	$panzerwerte{Kopf}{gewicht} = 0;
	$panzerwerte{Kopf}{kosten} = 0;
	$panzerwerte{Kopf}{anmerkungen} = "Eine bequeme Mütze";
	$panzerwerte{Arme}{name} = "Pullover";
	$panzerwerte{Arme}{panzerung} = 0;
	$panzerwerte{Arme}{kv} = 0;
	$panzerwerte{Arme}{gewicht} = 0;
	$panzerwerte{Arme}{kosten} = 0;
	$panzerwerte{Arme}{anmerkungen} = "Ein bequemer Pullover";
	$panzerwerte{Torso}{name} = "Pullover";
	$panzerwerte{Torso}{panzerung} = 0;
	$panzerwerte{Torso}{kv} = 0;
	$panzerwerte{Torso}{gewicht} = 0;
	$panzerwerte{Torso}{kosten} = 0;
	$panzerwerte{Torso}{anmerkungen} = "Ein bequemer Pullover";
	$panzerwerte{Beine}{name} = "Hose";
	$panzerwerte{Beine}{panzerung} = 0;
	$panzerwerte{Beine}{kv} = 0;
	$panzerwerte{Beine}{gewicht} = 0;
	$panzerwerte{Beine}{kosten} = 0;
	$panzerwerte{Beine}{anmerkungen} = "Eine bequeme Hose";
	
	$waffenwerte{"linke Hand"}{name} = "Nichts";
	$waffenwerte{"linke Hand"}{schaden} = "";
	$waffenwerte{"linke Hand"}{rw} = "";
	$waffenwerte{"linke Hand"}{kv} = "";
	$waffenwerte{"linke Hand"}{gewicht} = "";
	$waffenwerte{"linke Hand"}{kosten} = "";
	$waffenwerte{"linke Hand"}{anmerkungen} = "";
	$waffenwerte{"linke Hand"}{pb} = "";
	$waffenwerte{"linke Hand"}{fr} = "";
	$waffenwerte{"linke Hand"}{schuss} = "";
	$waffenwerte{"linke Hand"}{flaeche} = "";
	$waffenwerte{"rechte Hand"}{name} = "Nichts";
	$waffenwerte{"rechte Hand"}{schaden} = "";
	$waffenwerte{"rechte Hand"}{rw} = "";
	$waffenwerte{"rechte Hand"}{kv} = "";
	$waffenwerte{"rechte Hand"}{gewicht} = "";
	$waffenwerte{"rechte Hand"}{kosten} = "";
	$waffenwerte{"rechte Hand"}{anmerkungen} = "";
	$waffenwerte{"rechte Hand"}{pb} = "";
	$waffenwerte{"rechte Hand"}{fr} = "";
	$waffenwerte{"rechte Hand"}{schuss} = "";
	$waffenwerte{"rechte Hand"}{flaeche} = "";
	
	# Definieren der Bereiche für Körperteile (angepasste Koordinaten)
	my $head_coords = [114, 11, 144, 44];
	my $body_coords = [104, 45, 153, 123];
	my $right_arm_coords = [54, 32, 103, 63];
	my $left_arm_coords = [154, 32, 203, 60];
	#my $left_leg_coords = [130, 124, 162, 226];
	#my $right_leg_coords = [97, 124, 129, 226];
	my $beine_coords = [97, 124, 162, 226];
	my $left_hand_coords = [204, 32, 237, 60];
	my $right_hand_coords = [21, 32, 53, 60];
	
	# Erstellen der Klickbereiche
	create_clickable_area($head_coords, 'head', $canvas);
	create_clickable_area($body_coords, 'body', $canvas);
	create_clickable_area($left_arm_coords, 'left_arm', $canvas);
	create_clickable_area($right_arm_coords, 'right_arm', $canvas);
	#create_clickable_area($left_leg_coords, 'left_leg', $canvas);
	#create_clickable_area($right_leg_coords, 'right_leg', $canvas);
	create_clickable_area($beine_coords, 'beine', $canvas);
	create_clickable_area($left_hand_coords, 'left_hand', $canvas);
	create_clickable_area($right_hand_coords, 'right_hand', $canvas);

	# Ereignishandler für Klicks auf die Körperteile

    $row++;
	my $kopf_label = $dialog->Label(-text => "Kopf")->grid(-row => $row, -column => 3);
	my $kopf_entry = $dialog->Label(-text => "$panzerwerte{Kopf}{name}, P $panzerwerte{Kopf}{panzerung}")->grid(-row => $row, -column => 4, -sticky => 'w', -columnspan => 5);
	my $arme_label = $dialog->Label(-text => "Arme")->grid(-row => $row + 1, -column => 3);
	my $arme_entry = $dialog->Label(-text => "$panzerwerte{Arme}{name}, P $panzerwerte{Arme}{panzerung}")->grid(-row => $row + 1, -column => 4, -sticky => 'w', -columnspan => 5);
	my $lhand_label = $dialog->Label(-text => "Linke Hand")->grid(-row => $row + 2, -column => 3);
	my $lhand_entry = $dialog->Label(-text => "Nichts")->grid(-row => $row + 2, -column => 4, -sticky => 'w', -columnspan => 5);
	my $rhand_label = $dialog->Label(-text => "Rechte Hand")->grid(-row => $row + 3, -column => 3);
	my $rhand_entry = $dialog->Label(-text => "Nichts")->grid(-row => $row + 3, -column => 4, -sticky => 'w', -columnspan => 5);
	my $torso_label = $dialog->Label(-text => "Torso")->grid(-row => $row + 4, -column => 3);
	my $torso_entry = $dialog->Label(-text => "$panzerwerte{Torso}{name}, P $panzerwerte{Torso}{panzerung}")->grid(-row => $row + 4, -column => 4, -sticky => 'w', -columnspan => 5);
	my $beine_label = $dialog->Label(-text => "Beine")->grid(-row => $row + 5, -column => 3);
	my $beine_entry = $dialog->Label(-text => "$panzerwerte{Beine}{name}, P $panzerwerte{Beine}{panzerung}")->grid(-row => $row + 5, -column => 4, -sticky => 'w', -columnspan => 5);
	
	$canvas->bind('head', '<Button-1>', sub { update_item_label($dialog, 'Kopf', $kopf_entry, \%panzerwerte) });
	$canvas->bind('body', '<Button-1>', sub { update_item_label($dialog, 'Torso', $torso_entry, \%panzerwerte) });
	$canvas->bind('left_arm', '<Button-1>', sub { update_item_label($dialog, 'Arme', $arme_entry, \%panzerwerte) });
	$canvas->bind('right_arm', '<Button-1>', sub { update_item_label($dialog, 'Arme', $arme_entry, \%panzerwerte) });
	#$canvas->bind('left_leg', '<Button-1>', sub { update_item_label($dialog, 'linkes Bein', $beine_entry, \%panzerwerte) });
	#$canvas->bind('right_leg', '<Button-1>', sub { update_item_label($dialog, 'rechtes Bein', $beine_entry, \%panzerwerte) });
	$canvas->bind('beine', '<Button-1>', sub { update_item_label($dialog, 'Beine', $beine_entry, \%panzerwerte) });
	$canvas->bind('left_hand', '<Button-1>', sub { update_weapon_label($dialog, 'linke Hand', $lhand_entry, \%waffenwerte) });
	$canvas->bind('right_hand', '<Button-1>', sub { update_weapon_label($dialog, 'rechte Hand', $rhand_entry, \%waffenwerte) });
	
	my %wissen_skills = ();
	$wissen_skills{Allgemeinwissen} = 4;
    my $wissen_button = $dialog->Button(
        -text => "Wissensfertigkeiten",
        -command => sub {
            $verstand_benutzt = manage_wissen_skills("Fertigkeitspunkte", $dialog, \%wissen_skills, \$verstand_benutzt, get_bonus_attr_no_mod($attributes{Verstand}, 0), $skillpunkt_entry);
        }
    )->grid(-row => 22, -column => 2);

	$skills{Athletik} = 4;
	$skills{Heimlichkeit} = 4;
	$skills{Überreden} = 4;
	$skills{Wahrnehmung} = 4;
	foreach my $skill (@char_skills) {
		$skills_fields{$skill}{label} = $dialog->Label(-text => $skill)->grid(-row => $row, -column => 0, -sticky => 'w');
		$balloon->attach($skills_fields{$skill}{label}, -balloonmsg => "Verknüpftes Attribut: $char_skill_attributes{$skill}");
		$skills_fields{$skill}{skillmod_label} = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => $row, -column => 0, -sticky => 'n');
		$skills_fields{$skill}{skillmod_entry} = $dialog->Entry(-width => 3, -text => 0, -validate => 'key', -validatecommand => sub {
			my $new_value = shift;
			return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
			return 0;
		})->grid(-row => $row, -column => 0, -sticky => 'e');
		
		$skills_fields{$skill}{entry} = $dialog->Label(-text => "W$skills{$skill}")->grid(-row => $row, -column => 1, -sticky => 'w');
		
		$skills_fields{$skill}{skillmod_entry}->bind('<KeyRelease>', sub {
			my $mod_value = $skills_fields{$skill}{skillmod_entry}->get();
			if ($mod_value =~ /^[\+-]?\d+$/) {
				update_display($skills{$skill}, $mod_value, $skills_fields{$skill}{entry}, $skill);
				$skill_mods{$skill} = $mod_value;
				if($skill eq "Kämpfen" || $skill eq "Ausweichen")
				{
					update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis,	$parademod_entry, $paradegs_entry);
				}
			}
		});
		
				my $increase_button = $dialog->Button(
			-text => "+",
			-command => sub {
				if($skillpunkt_entry->cget('-text') == 0)
				{
					$dialog->messageBox(
					-type    => 'Ok',
					-icon    => 'error',
					-title   => 'Keine Fertigkeitspunkte mehr',
					-message => "Keine Fertigkeitspunkte mehr zum Verteilen!"
					);
					return;
				}

				my $current_skill_value_str = $skills{$skill};
				my $new_skill_value_str;

				# Nächsten Fertigkeitswert bestimmen
				if ($current_skill_value_str =~ /^(\d+)$/) {
					my $number = $1;
					if ($number == 0) { $new_skill_value_str = 4; }
					elsif ($number < 12) { $new_skill_value_str = $number + 2; }
					else { $new_skill_value_str = "12+1"; }
				} elsif ($current_skill_value_str =~ /^12\+(\d+)$/) {
					$new_skill_value_str = "12+" . ($1 + 1);
				}

				# Kosten bestimmen
				my $cost = 1;
				my $linked_attribute = $char_skill_attributes{$skill};
				my $attribute_value_str = $attributes{$linked_attribute};

				# Numerische Werte für den Vergleich
				my $numeric_new_skill = ($new_skill_value_str =~ /^12\+(\d+)$/) ? 12 + $1 : $new_skill_value_str;
				my $numeric_attribute = ($attribute_value_str =~ /^12\+(\d+)$/) ? 12 + $1 : $attribute_value_str;
				
				if ($numeric_new_skill > $numeric_attribute) {
					$cost = 2;
				}
				# Das Kaufen einer neuen Fertigkeit (auf W4) kostet immer 1 Punkt
				if ($current_skill_value_str == 0) {
					$cost = 1;
				}

				# Prüfen, ob genug Punkte vorhanden sind
				if ($skillpunkt_entry->cget('-text') < $cost) {
					$dialog->messageBox(
						-type    => 'Ok',
						-icon    => 'error',
						-title   => 'Nicht genug Fertigkeitspunkte',
						-message => "Die Steigerung kostet $cost Punkte, aber es sind nur " . $skillpunkt_entry->cget('-text') . " verfügbar."
					);
					return;
				}

				# Änderungen anwenden
				$skills{$skill} = $new_skill_value_str;
				$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - $cost);
				
				update_display($skills{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill);
				if($skill eq "Kämpfen" || $skill eq "Ausweichen")
				{
					update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis,	$parademod_entry, $paradegs_entry);
				}
			}
		)->grid(-row => $row, -column => 1, -sticky => 'n', -ipadx=> 8);

		my $decrease_button = $dialog->Button(
			-text => "-",
			-command => sub {
				my $current_skill_value_str = $skills{$skill};
				return if $current_skill_value_str == 0; # Nichts zu tun

				# Kostenrückerstattung bestimmen
				my $refund = 1;
				my $linked_attribute = $char_skill_attributes{$skill};
				my $attribute_value_str = $attributes{$linked_attribute};

				# Numerische Werte für den Vergleich
				my $numeric_current_skill = ($current_skill_value_str =~ /^12\+(\d+)$/) ? 12 + $1 : $current_skill_value_str;
				my $numeric_attribute = ($attribute_value_str =~ /^12\+(\d+)$/) ? 12 + $1 : $attribute_value_str;
				
				if ($numeric_current_skill > $numeric_attribute) {
					$refund = 2;
				}
				# Das Senken von W4 auf 0 gibt immer 1 Punkt zurück
				if ($current_skill_value_str == 4) {
					$refund = 1;
				}

				# Vorherigen Fertigkeitswert bestimmen
				my $previous_skill_value_str;
				if ($current_skill_value_str =~ /^12\+(\d+)$/) {
					my $number = $1;
					$previous_skill_value_str = ($number > 1) ? "12+" . ($number - 1) : 12;
				} elsif ($current_skill_value_str =~ /^(\d+)$/) {
					my $number = $1;
					if ($number == 4) { $previous_skill_value_str = 0; }
					elsif ($number > 4) { $previous_skill_value_str = $number - 2; }
				}
				
				# Änderungen anwenden
				$skills{$skill} = $previous_skill_value_str;
				$skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + $refund);
				
				update_display($skills{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill);
				if($skill eq "Kämpfen" || $skill eq "Ausweichen")
				{
					update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis,	$parademod_entry, $paradegs_entry);
				}
			}
		)->grid(-row => $row, -column => 1, -sticky => 'e', -ipadx=> 8);
		$row++;
	}

    # Vermögen
    my $vermoegen_label = $dialog->Label(-text => "Vermögen")->grid(-row => $row - 2, -column => 2);
    my $vermoegen_entry = $dialog->Entry(-textvariable => 500)->grid(-row => $row - 2, -column => 3, -sticky => 'w');

    # Lebensstil
    my $lebensstil_label = $dialog->Label(-text => "Lebensstil")->grid(-row => $row - 1, -column => 2);
    my $lebensstil_entry = $dialog->Entry()->grid(-row => $row - 1, -column => 3, -sticky => 'w');

    # Talents
    my $talent_listbox = create_talent_frame($talentpunkt_entry, $dialog, $row);

    # VR-Ausrüstung
    my $vr_label = $dialog->Label(-text => "VR-Ausrüstung")->grid(-row => $row, -column => 2);
    $row++;
    my $vr_listbox = $dialog->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->grid(-row => $row, -column => 2, -sticky => 'w');
    $vr_listbox->Subwidget('listbox')->bind('<Enter>', sub{$vr_listbox->Subwidget('listbox')->focus()});
    $vr_listbox->Subwidget('listbox')->bind('<Leave>', sub {$dialog->focus();});

    my $vr_button_frame = $dialog->Frame()->grid(-row => $row, -column => 3, -sticky => 'w');
    $vr_button_frame->Button(
        -text => "+",
        -command => sub { add_vr_item($dialog, $vr_listbox) }
    )->pack(-side => 'top');
    $vr_button_frame->Button(
        -text => "-",
        -command => sub { delete_vr_item($dialog, $vr_listbox) }
    )->pack(-side => 'top');
    $row++;

    # Handicaps
    my $handicap_listbox = create_handicap_frame($talentpunkt_entry, $dialog, $row);

    # Gegenstände
    my $items_label = $dialog->Label(-text => "Ausrüstung")->grid(-row => $row, -column => 2);
    $row++;
    my $items_listbox = $dialog->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->grid(-row => $row, -column => 2, -sticky => 'w');
    $items_listbox->Subwidget('listbox')->bind('<Enter>', sub{$items_listbox->Subwidget('listbox')->focus()});
    $items_listbox->Subwidget('listbox')->bind('<Leave>', sub {$dialog->focus();});

    my $items_button_frame = $dialog->Frame()->grid(-row => $row, -column => 3, -sticky => 'w');
    $items_button_frame->Button(
        -text => "+",
        -command => sub { add_items_item($dialog, $items_listbox, 0, 'Gegenstand') }
    )->pack(-side => 'top');
    $items_button_frame->Button(
        -text => "-",
        -command => sub { delete_items_item($dialog, $items_listbox) }
    )->pack(-side => 'top');
    $row+=2;
    # Avatar Management
    my @avatars;
	push @avatars, {
		name => $av_name,
		game => 'Uniworld',
		main => 1
	};
    my $avatar_frame = $dialog->Frame()->grid(-row => $row, -column => 0, -columnspan => 2, -sticky => 'w');
    $row++;
    manage_avatars($avatar_frame, \@avatars, \%attributes, \%attr_mods, \%skills, \%skill_mods);

    # Save Button
    $dialog->Button(
        -text    => "Charakter Speichern",
        -command => sub {
			if($attrpunkt_entry->cget('-text') != 0 || $skillpunkt_entry->cget('-text') != 0 || $talentpunkt_entry->cget('-text') != 0)
			{
				$dialog->messageBox(
				-type    => 'Ok',
				-icon    => 'info',
				-title   => 'Punkte verteilen',
				-message => "Bitte erst alle Attributs- Talent- & Fertigkeits-Punkte verteilen!"
				);
			}
			else
			{
				$next_id++;
				$characters->{$next_id} = {
					id          => $next_id,
					name        => $name_entry->get(),
					location    => $location_entry->get(),
					description => $description_entry->get(),
					vermoegen   => $vermoegen_entry->get(),
					lebensstil => $lebensstil_entry->get(),
					alter => $alter_entry->get(),
					vr_ausruestung => [$vr_listbox->get(0, 'end')],
					items => [$items_listbox->get(0, 'end')],
					bennies     => $bennies_entry->get(),
					benniesmax     => $benniesmax_entry->get(),
					panzer  => { %panzerwerte },
					wissen => { %wissen_skills },
					waffen         => { %waffenwerte },
					wunden      => $wunden_entry->get(),
					wundenmax      => $wundenmax_entry->get(),
					bewegungmod => $bewegungmod_entry->get(),
					parademod   => $parademod_entry->get(),
					robustmod   => $robustmod_entry->get(),
					onlinemod   => $onlinemod_entry->get(),
					xp          => 0,
					xp_unused     => 0,
					verstand_benutzt => $verstand_benutzt,
					rank        => 'Anfänger',
					attributes  => { %attributes },
					attr_mods  => { %attr_mods },
					skills      => { %skills },
					skill_mods  => { %skill_mods },
					talents     => [$talent_listbox->get(0, 'end')],
					handicaps   => [$handicap_listbox->get(0, 'end')],
					avatars     => [@avatars],
					attr_steig  => { "Anfänger" => 0, "Fortgeschritten" => 0, "Veteran" => 0, "Heroisch" => 0, "Legendär" => 0}
				};
				update_character_list();
				$add_char->destroy();
			}
        }
    )->grid(-row => $row, -column => 1, -sticky => 'w');
}

# Character editing dialog
sub edit_character {
	unless(defined $current_character)
	{
		$mw->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Charakter wählen',
            -message => "Bitte einen Charakter auswählen."
        );
		return;
	}

    my $edit_char = $mw->Toplevel();
    focus_dialog($edit_char, "Charakter bearbeiten", $mw);
    $edit_char->geometry("950x950");  # Width x Height in pixels
	my $scrolled_area = $edit_char->Scrolled(
        'Frame',
        -scrollbars => 'osoe'
    )->pack(-fill => 'both', -expand => 1);
	my $dialog = $scrolled_area->Subwidget('scrolled');
	my $spacer = $dialog->Label(-text => "", -width => 42)->grid(-row => 0, -column => 0);
	my $verstand_benutzt = $current_character->{verstand_benutzt};
    my $row = 0;
	
	my %attributes = %{$current_character->{attributes}};
	my %attr_mods = %{$current_character->{attr_mods}};

    # Name
    my $name_label = $dialog->Label(-text => "Name")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $name_entry = $dialog->Entry(-textvariable => \$current_character->{name})->grid(-row => $row, -column => 1, -sticky => 'w');

    # XP
    my $xp_label = $dialog->Label(-text => "Erfahrungspunkte")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $xp_entry = $dialog->Label(-width => 3, -text => $current_character->{xp})->grid(-row => $row, -column => 2, -sticky => 'n');
	
	# XP über
	my $xp_unused_label = $dialog->Label(-text => "Erfahrungspunkte über")->grid(-row => $row, -column => 3, -sticky => 'w');
    my $xp_unused_entry = $dialog->Label(-text => $current_character->{xp_unused})->grid(-row => $row, -column => 3, -sticky => 'e');
    $row++;

    # Wohnort
    my $location_label = $dialog->Label(-text => "Wohnort")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $location_entry = $dialog->Entry(-textvariable => \$current_character->{location})->grid(-row => $row, -column => 1, -sticky => 'w');

    # Rank
    my $rank_label = $dialog->Label(-text => "Rang")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $rank_entry = $dialog->Label(-width => 11, -text => $current_character->{rank})->grid(-row => $row, -column => 2, -sticky => 'n');
	
	my $stufenaufstieg = $dialog->Button(
			-text => "Stufenaufstieg",
			-command => sub {
				$xp_unused_entry->configure(-text => $xp_unused_entry->cget('-text') + 2);
				$xp_entry->configure(-text => $xp_entry->cget('-text') + 2);
				if($xp_entry->cget('-text') == 32)
				{
					print_rank_message($dialog, $rank_entry, 'Legendär', '2 Erfahrungspunkte');
				}
				elsif($xp_entry->cget('-text') == 24)
				{
					print_rank_message($dialog, $rank_entry, 'Heroisch', '2 Erfahrungspunkte');
				}
				elsif($xp_entry->cget('-text') == 16)
				{
					print_rank_message($dialog, $rank_entry, 'Veteran', '2 Erfahrungspunkte');
				}
				elsif($xp_entry->cget('-text') == 8)
				{
					print_rank_message($dialog, $rank_entry, 'Fortgeschritten', '2 Erfahrungspunkte');
				}
				else
				{
					$dialog->messageBox(
					-type    => 'Ok',
					-icon    => 'info',
					-title   => 'Stufenaufstieg',
					-message => "Herzlichen Glückwunsch!\nUnd 2 Erfahrungspunkte zum Verteilen gibt es auch noch. :)"
					);
				}
			}
	)->grid(-row => $row, -column => 3, -sticky => 'w');

    $row++;

    # Beschreibung
    my $description_label = $dialog->Label(-text => "Beschreibung")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $description_entry = $dialog->Entry(-textvariable => \$current_character->{description})->grid(-row => $row, -column => 1, -sticky => 'w');

    # Bennies
    my $bennies_label = $dialog->Label(-text => "Bennies")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $bennies_entry = $dialog->Entry(-width => 2, -textvariable => \$current_character->{bennies})->grid(-row => $row, -column => 2, -sticky => 'n');
    my $benniesmax_label = $dialog->Label(-width => 3, -text => "von ")->grid(-row => $row, -column => 2, -sticky => 'e', -ipadx=> 35);
    my $benniesmax_entry = $dialog->Entry(-width => 2, -textvariable => \$current_character->{benniesmax})->grid(-row => $row, -column => 2, -sticky => 'e');
    $row++;
	
	# Alter
    my $alter_label = $dialog->Label(-text => "Alter")->grid(-row => $row, -column => 0, -sticky => 'w');
    my $alter_entry = $dialog->Entry(-textvariable => \$current_character->{alter})->grid(-row => $row, -column => 1, -sticky => 'w');

    # Wunden
    my $wunden_label = $dialog->Label(-text => "Wunden")->grid(-row => $row, -column => 2, -sticky => 'w');
    my $wunden_entry = $dialog->Entry(-width => 2, -textvariable => \$current_character->{wunden})->grid(-row => $row, -column => 2, -sticky => 'n');
    my $wundenmax_label = $dialog->Label(-width => 3, -text => "von ")->grid(-row => $row, -column => 2, -sticky => 'e', -ipadx=> 35);
    my $wundenmax_entry = $dialog->Entry(-width => 2, -textvariable => \$current_character->{wundenmax})->grid(-row => $row, -column => 2, -sticky => 'e');
    $row+=2;

	# Online-Zeit
	my $balloon = $dialog->Balloon();
	my $online_label = $dialog->Label(-text => "Online-Zeit")->grid(-row => 8, -column => 2, -sticky => 'w');
    my $online_basis = $dialog->Label(-width => 3, -text => 2)->grid(-row => 8, -column => 2, -sticky => 'n');
    my $onlinemod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => 8, -column => 2, -sticky => 'e', -ipadx=> 10);
    my $onlinemod_entry = $dialog->Entry(-width => 3, -textvariable => $current_character->{onlinemod}, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 8, -column => 3, -sticky => 'w');
    my $onlineges_label = $dialog->Label(-text => "Gesamt")->grid(-row => 8, -column => 3, -sticky => 'n');
    my $onlinegs_entry = $dialog->Label(-width => 3, -text => $online_basis->cget('-text') + $current_character->{onlinemod})->grid(-row => 8, -column => 3, -sticky => 'e', -ipadx=> 10);
	$balloon->attach($onlinegs_entry, -balloonmsg => ($online_basis->cget('-text') + $current_character->{onlinemod}). " h ohne Malus, dann bis zu " . ($online_basis->cget('-text') + 2 + $current_character->{onlinemod}) . " h mit Malus 2, dann bis zu " . ($online_basis->cget('-text') + 4 + $current_character->{onlinemod}) . " h mit Malus 4, dann Pause benötigt.");
    $onlinemod_entry->bind('<KeyRelease>', sub {
        my $mod_value = $onlinemod_entry->get();
        if ($mod_value =~ /^[\+-]?\d+$/) {
            update_online($attributes{"Körperliche Verfassung"}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{"Körperliche Verfassung"});
        } else {
            $dialog->messageBox(
                -type    => 'Ok',
                -icon    => 'error',
                -title   => 'Online-Zeit-Mod fehlerhaft',
                -message => "Bitte den Wert im Mod-Feld bei Online-Zeit prüfen.\nSetze den Gesamt-Wert auf den Basis-Wert."
            );
            $onlinegs_entry->configure(-text => $online_basis->cget('-text'));
        }
    });
	
	my %skills_fields = ();
	my %skills = %{$current_character->{skills}};
	my %skill_mods = %{$current_character->{skill_mods} || {}};  # Use empty hash if skill_mods doesn't exist yet
	
	my $parade_basis;
	my $parademod_entry;
	my $paradegs_entry;
	my $robust_basis;
	my $robustmod_entry;
	my $robustgs_entry;
	
	# Attribute
	my $attr_label = $dialog->Label(-text => "Attribute")->grid(-row => 4, -column => 0, -columnspan => 2);
	
	my %attr_steig = %{$current_character->{attr_steig}};
	# Attribute müssen noch angepasst werden! + wurde noch nichts gemacht. $attrpunkt_entry gibt es nicht. Hier auch auf XP oder Charakerpunkte wechseln
	foreach my $attribute (@char_attributes) {
		my $label = $dialog->Label(-text => $attribute)->grid(-row => $row, -column => 0, -sticky => 'w');
		my $attrmod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => $row, -column => 0, -sticky => 'n');
		my $attremod_entry = $dialog->Entry(-width => 3, -text => $attr_mods{$attribute}, -validate => 'key', -validatecommand => sub {
			my $new_value = shift;
			return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
			return 0;
		})->grid(-row => $row, -column => 0, -sticky => 'e');
		

		my $entry = $dialog->Label()->grid(-row => $row, -column => 1, -sticky => 'w');
		update_display($attributes{$attribute}, $attr_mods{$attribute}, $entry);
		$attremod_entry->bind('<KeyRelease>', sub {
			my $mod_value = $attremod_entry->get();
			if ($mod_value =~ /^[\+-]?\d+$/) {
				update_display($attributes{$attribute}, $mod_value, $entry);
				$attr_mods{$attribute} = $mod_value;
			}
			if ($attribute eq "Körperliche Verfassung")
			{
				update_online($attributes{"Körperliche Verfassung"}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{"Körperliche Verfassung"});
				update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
			}
			elsif($attribute eq "Reaktion")
			{
				update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry);
			}
		});
		my $increase_button = $dialog->Button(
			-text => "+",
			-command => sub {
				if($xp_unused_entry->cget('-text') < 2)
				{
					$dialog->messageBox(
					-type    => 'Ok',
					-icon    => 'error',
					-title   => 'Nicht genug XP',
					-message => "Night genug freie Erfahrungspunkte! Attribute kosten 2 XP."
					);
				}
				else
				{
					my $aufstiege = int(($xp_entry->cget('-text') / 2) - 16);
					if($rank_entry->cget('-text') eq "Legendär" && ($attr_steig{$rank_entry->cget('-text')} > $aufstiege))
					{
						$dialog->messageBox(
						-type    => 'Ok',
						-icon    => 'error',
						-title   => 'Bereits gesteigert',
						-message => "Legendäre Charaktere können nur alle 2 Aufstiege ein Attribut steigern!"
						);
					}
					elsif($rank_entry->cget('-text') ne "Legendär" && $attr_steig{$rank_entry->cget('-text')} > 0)
					{
						$dialog->messageBox(
						-type    => 'Ok',
						-icon    => 'error',
						-title   => 'Bereits gesteigert',
						-message => "Du hast auf diesem Rang bereits ein Attribut gesteigert!"
						);
					}
					else
					{
						if($rank_entry->cget('-text') ne "Legendär")
						{
							$attr_steig{$rank_entry->cget('-text')}++;
						}
						else
						{
							$attr_steig{$rank_entry->cget('-text')}+=2;
						}
						$xp_unused_entry->configure(-text => $xp_unused_entry->cget('-text') - 2);
						my $current_value = $attributes{$attribute};
						if ($current_value =~ /^(\d+)$/) {
							my $number = $1;
							if ($number < 12) {
								$number += 2;
								$attributes{$attribute} = $number;
							} elsif ($number == 12) {
								$attributes{$attribute} = "12+1";
							}
						} elsif ($current_value =~ /^12\+(\d+)$/) {
							my $number = $1 + 1;
							$attributes{$attribute} = "12+$number";
						}
						update_display($attributes{$attribute}, $attr_mods{$attribute}, $entry);
						if ($attribute eq "Körperliche Verfassung")
						{
							update_online($attributes{"Körperliche Verfassung"}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{"Körperliche Verfassung"});
							update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
						}
						elsif($attribute eq "Reaktion")
						{
							update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry);
						}
					}
				}
			}
		)->grid(-row => $row, -column => 1, -sticky => 'n', -ipadx => 8);

		my $decrease_button = $dialog->Button(
			-text => "-",
			-command => sub
			{
				if($attribute eq 'Verstand')
				{
					if(get_bonus_attr_no_mod($attributes{Verstand}, 0) - $verstand_benutzt > 1)
					{
						my $current_value = $attributes{$attribute};
						if ($current_value =~ /^(\d+)$/)
						{
							my $number = $1;
							if ($number == 4) {
								$dialog->messageBox(
									-type    => 'Ok',
									-icon    => 'info',
									-title   => 'Attribut senken',
									-message => "Attribute können nicht niedriger als W4 sein."
								);
							}
							elsif ($number > 4)
							{
								$xp_unused_entry->configure(-text => $xp_unused_entry->cget('-text') + 2);
								$number -= 2;
								$attributes{$attribute} = $number;
							}
						}
						elsif ($current_value =~ /^12\+(\d+)$/)
						{
							my $number = $1;
							$xp_unused_entry->configure(-text => $xp_unused_entry->cget('-text') + 2);
							if ($number > 1)
							{
								$number--;
								$attributes{$attribute} = "12+$number";
							}
							else
							{
								$attributes{$attribute} = 12;
							}
						}
						$attr_steig{$rank_entry->cget('-text')}--;
						update_display($attributes{$attribute}, $attr_mods{$attribute}, $entry);
					}
					else
					{
						$dialog->messageBox(
								-type    => 'Ok',
								-icon    => 'info',
								-title   => 'Verstand senken',
								-message => "Verstand kann nicht weiter gesenkt werden, da es für Wissensfertigkeiten genutzt wird.\nBitte erst Wissensfertigkeiten senken."
							);
					}
				}
				else
				{
					my $current_value = $attributes{$attribute};
					if ($current_value =~ /^(\d+)$/)
					{
						my $number = $1;
						if ($number == 4) {
							$dialog->messageBox(
								-type    => 'Ok',
								-icon    => 'info',
								-title   => 'Attribut senken',
								-message => "Attribute können nicht niedriger als W4 sein."
							);
							return;
						}
						elsif ($number > 4)
						{
							$xp_unused_entry->configure(-text => $xp_unused_entry->cget('-text') + 2);
							$attr_steig{$rank_entry->cget('-text')}--;
							$number -= 2;
							$attributes{$attribute} = $number;
						}
					}
					elsif ($current_value =~ /^12\+(\d+)$/)
					{
						my $number = $1;
						$xp_unused_entry->configure(-text => $xp_unused_entry->cget('-text') + 2);
						$attr_steig{$rank_entry->cget('-text')}--;
						if ($number > 1)
						{
							$number--;
							$attributes{$attribute} = "12+$number";
						}
						else
						{
							$attributes{$attribute} = 12;
						}
					}
					update_display($attributes{$attribute}, $attr_mods{$attribute}, $entry);
					if ($attribute eq "Körperliche Verfassung")
					{
						update_online($attributes{"Körperliche Verfassung"}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{"Körperliche Verfassung"});
						update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
					}
					elsif($attribute eq "Reaktion")
					{
						update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry);
					}
				}
			}
		)->grid(-row => $row, -column => 1, -sticky => 'e', -ipadx => 8);

		$row++;
	}

    # Abgeleitete Werte
    my $abglw_label = $dialog->Label(-text => "Abgeleitete Werte")->grid(-row => 4, -column => 2, -columnspan => 4);
    $row++;

    my $bewegung_label = $dialog->Label(-text => "Bewegung")->grid(-row => 5, -column => 2, -sticky => 'w');
    my $bewegung_basis = $dialog->Label(-width => 3, -text => 6)->grid(-row => 5, -column => 2, -sticky => 'n');
    my $bewegungmod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => 5, -column => 2, -sticky => 'e', -ipadx=> 10);
    my $bewegungmod_entry = $dialog->Entry(-width => 3, -textvariable => \$current_character->{bewegungmod}, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 5, -column => 3, -sticky => 'w');
    my $bewegungges_label = $dialog->Label(-text => "Gesamt")->grid(-row => 5, -column => 3, -sticky => 'n');
    my $bewegunggs_entry = $dialog->Label(-width => 3, -text => $bewegung_basis->cget('-text') + $current_character->{bewegungmod} . '"')->grid(-row => 5, -column => 3, -sticky => 'e', -ipadx=> 10);

    $bewegungmod_entry->bind('<KeyRelease>', sub {
        my $mod_value = $bewegungmod_entry->get();
        if ($mod_value =~ /^[\+-]?\d+$/) {
            $bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') + $mod_value . '"');
        } else {
            $dialog->messageBox(
                -type    => 'Ok',
                -icon    => 'error',
                -title   => 'Bewegungs-Mod fehlerhaft',
                -message => "Bitte den Wert im Mod-Feld bei Bewegung prüfen.\nSetze den Gesamt-Wert auf den Basis-Wert."
            );
            $bewegunggs_entry->configure(-text => $bewegung_basis->cget('-text') . '"');
        }
    });

	# Parade
    my $parade_label = $dialog->Label(-text => "Parade")->grid(-row => 6, -column => 2, -sticky => 'w');
    $parade_basis = $dialog->Label(-width => 3, -text => 2)->grid(-row => 6, -column => 2, -sticky => 'n');
    my $parademod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => 6, -column => 2, -sticky => 'e', -ipadx=> 10);
    $parademod_entry = $dialog->Entry(-width => 3, -textvariable => \$current_character->{parademod}, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 6, -column => 3, -sticky => 'w');
    my $paradeges_label = $dialog->Label(-text => "Gesamt")->grid(-row => 6, -column => 3, -sticky => 'n');
    $paradegs_entry = $dialog->Label(-width => 3, -text => $parade_basis->cget('-text') + $current_character->{parademod})->grid(-row => 6, -column => 3, -sticky => 'e', -ipadx=> 10);

    $parademod_entry->bind('<KeyRelease>', sub {
        my $mod_value = $parademod_entry->get();
        if ($mod_value =~ /^[\+-]?\d+$/) {
			update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry);
        } else {
            $dialog->messageBox(
                -type    => 'Ok',
                -icon    => 'error',
                -title   => 'Parade-Mod fehlerhaft',
                -message => "Bitte den Wert im Mod-Feld bei Parade prüfen.\nSetze den Gesamt-Wert auf den Basis-Wert."
            );
            $paradegs_entry->configure(-text => $parade_basis->cget('-text'));
        }
    });
	$balloon->attach($parade_basis, -balloonmsg => "Basis: 2 + ((Kämpfen + Mod) / 2) + ((Reaktion + Mod) / 4) + ((Ausweichen + Mod) / 2), aufgerundet");
	$balloon->attach($paradegs_entry, -balloonmsg => "Gesamt: Basis + Modifikator");
	
	# Robustheit
    my $robust_label = $dialog->Label(-text => "Robustheit")->grid(-row => 7, -column => 2, -sticky => 'w');
    $robust_basis = $dialog->Label(-width => 3, -text => 2)->grid(-row => 7, -column => 2, -sticky => 'n');
    my $robustmod_label = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => 7, -column => 2, -sticky => 'e', -ipadx=> 10);
    $robustmod_entry = $dialog->Entry(-width => 3, -textvariable => \$current_character->{robustmod}, -validate => 'key', -validatecommand => sub {
        my $new_value = shift;
        return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
        return 0;
    })->grid(-row => 7, -column => 3, -sticky => 'w');
    my $robustges_label = $dialog->Label(-text => "Gesamt")->grid(-row => 7, -column => 3, -sticky => 'n');
    $robustgs_entry = $dialog->Label(-width => 3)->grid(-row => 7, -column => 3, -sticky => 'e', -ipadx=> 10);
	update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
    $robustmod_entry->bind('<KeyRelease>', sub {
        update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
    });
	
	update_online($attributes{"Körperliche Verfassung"}, $online_basis, $onlinemod_entry->get(), $onlinegs_entry, $balloon, $attr_mods{"Körperliche Verfassung"});
	update_robust(\%attributes, \%attr_mods, $robust_basis, $robustmod_entry, $robustgs_entry);
	update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis, $parademod_entry, $paradegs_entry);

    my $inventar_label = $dialog->Label(-text => "Inventarverwaltung")->grid(-row => $row, -column => 3);

    # Charakterbild
    my $dirname = get_script_dir();

    unless (-e "$dirname/avatar.gif") {
        die "Fehler: Bilddatei avatar.gif konnte nicht gefunden werden.\n";
    }

    my $image = $dialog->Photo(-file => "$dirname/avatar.gif");
    my $canvas = $dialog->Canvas(
    -width  => 257,
    -height => 257
    )->grid(
    -row      => $row + 1,       # Startzeile
    -column   => 2,       # Spalte rechts neben den anderen Widgets
    -rowspan  => 10,      # Erstreckt sich über 10 Zeilen
    -columnspan  => 2,      # Erstreckt sich über 10 Zeilen
    -sticky   => 'nsew'   # Füllt den zugewiesenen Bereich aus
    );
    $canvas->createImage(0, 0, -image => $image, -anchor => 'nw');

    my %waffenwerte = %{$current_character->{waffen}};
    my %panzerwerte = %{$current_character->{panzer}};

    # Definieren der Bereiche für Körperteile (angepasste Koordinaten)
    my $head_coords = [114, 11, 144, 44];
    my $body_coords = [104, 45, 153, 123];
    my $right_arm_coords = [54, 32, 103, 63];
    my $left_arm_coords = [154, 32, 203, 60];
    my $beine_coords = [97, 124, 162, 226];
    my $left_hand_coords = [204, 32, 237, 60];
    my $right_hand_coords = [21, 32, 53, 60];

    # Erstellen der Klickbereiche
    create_clickable_area($head_coords, 'head', $canvas);
    create_clickable_area($body_coords, 'body', $canvas);
    create_clickable_area($left_arm_coords, 'left_arm', $canvas);
    create_clickable_area($right_arm_coords, 'right_arm', $canvas);
    create_clickable_area($beine_coords, 'beine', $canvas);
    create_clickable_area($left_hand_coords, 'left_hand', $canvas);
    create_clickable_area($right_hand_coords, 'right_hand', $canvas);

    # Ereignishandler für Klicks auf die Körperteile
    $row++;
    my $kopf_label = $dialog->Label(-text => "Kopf")->grid(-row => $row, -column => 3);
    my $kopf_entry = $dialog->Label(-text => "$panzerwerte{Kopf}{name}, P $panzerwerte{Kopf}{panzerung}")->grid(-row => $row, -column => 4, -sticky => 'w', -columnspan => 5);
    my $arme_label = $dialog->Label(-text => "Arme")->grid(-row => $row + 1, -column => 3);
    my $arme_entry = $dialog->Label(-text => "$panzerwerte{Arme}{name}, P $panzerwerte{Arme}{panzerung}")->grid(-row => $row + 1, -column => 4, -sticky => 'w', -columnspan => 5);
    my $lhand_label = $dialog->Label(-text => "Linke Hand")->grid(-row => $row + 2, -column => 3);
    my $lhand_entry = $dialog->Label(-text => "$waffenwerte{'linke Hand'}{name}")->grid(-row => $row + 2, -column => 4, -sticky => 'w', -columnspan => 5);
    my $rhand_label = $dialog->Label(-text => "Rechte Hand")->grid(-row => $row + 3, -column => 3);
    my $rhand_entry = $dialog->Label(-text => "$waffenwerte{'rechte Hand'}{name}")->grid(-row => $row + 3, -column => 4, -sticky => 'w', -columnspan => 5);
    my $torso_label = $dialog->Label(-text => "Torso")->grid(-row => $row + 4, -column => 3);
    my $torso_entry = $dialog->Label(-text => "$panzerwerte{Torso}{name}, P $panzerwerte{Torso}{panzerung}")->grid(-row => $row + 4, -column => 4, -sticky => 'w', -columnspan => 5);
    my $beine_label = $dialog->Label(-text => "Beine")->grid(-row => $row + 5, -column => 3);
    my $beine_entry = $dialog->Label(-text => "$panzerwerte{Beine}{name}, P $panzerwerte{Beine}{panzerung}")->grid(-row => $row + 5, -column => 4, -sticky => 'w', -columnspan => 5);

    $canvas->bind('head', '<Button-1>', sub { update_item_label($dialog, 'Kopf', $kopf_entry, \%panzerwerte) });
    $canvas->bind('body', '<Button-1>', sub { update_item_label($dialog, 'Torso', $torso_entry, \%panzerwerte) });
    $canvas->bind('left_arm', '<Button-1>', sub { update_item_label($dialog, 'Arme', $arme_entry, \%panzerwerte) });
    $canvas->bind('right_arm', '<Button-1>', sub { update_item_label($dialog, 'Arme', $arme_entry, \%panzerwerte) });
    $canvas->bind('beine', '<Button-1>', sub { update_item_label($dialog, 'Beine', $beine_entry, \%panzerwerte) });
    $canvas->bind('left_hand', '<Button-1>', sub { update_weapon_label($dialog, 'linke Hand', $lhand_entry, \%waffenwerte) });
    $canvas->bind('right_hand', '<Button-1>', sub { update_weapon_label($dialog, 'rechte Hand', $rhand_entry, \%waffenwerte) });

	my %wissen_skills = %{$current_character->{wissen}};
    my $wissen_button = $dialog->Button(
        -text => "Wissensfertigkeiten",
        -command => sub {
            $verstand_benutzt = manage_wissen_skills("Erfahrungspunkte", $dialog, \%wissen_skills, \$verstand_benutzt, get_bonus_attr_no_mod($attributes{Verstand}, 0), $xp_unused_entry);
        }
    )->grid(-row => 22, -column => 2);

    # Skills
	my $skill_label = $dialog->Label(-text => "Fertigkeiten")->grid(-row => $row, -column => 0, -columnspan => 2);

	foreach my $skill (@char_skills) {
		$skills_fields{$skill}{label} = $dialog->Label(-text => $skill)->grid(-row => $row, -column => 0, -sticky => 'w');
		$balloon->attach($skills_fields{$skill}{label}, -balloonmsg => "Verknüpftes Attribut: $char_skill_attributes{$skill}");
		$skills_fields{$skill}{skillmod_label} = $dialog->Label(-width => 3, -text => "Mod")->grid(-row => $row, -column => 0, -sticky => 'n');
		$skills_fields{$skill}{skillmod_entry} = $dialog->Entry(-width => 3, -text => $skill_mods{$skill} || 0, -validate => 'key', -validatecommand => sub {
			my $new_value = shift;
			return 1 if $new_value =~ /^[\+-]?\d*$/;  # Allow digits and optional leading minus & plus sign
			return 0;
		})->grid(-row => $row, -column => 0, -sticky => 'e');
		
		$skills_fields{$skill}{entry} = $dialog->Label()->grid(-row => $row, -column => 1, -sticky => 'w');
		update_display($skills{$skill}, $skill_mods{$skill} || 0, $skills_fields{$skill}{entry});
		
		$skills_fields{$skill}{skillmod_entry}->bind('<KeyRelease>', sub {
			my $mod_value = $skills_fields{$skill}{skillmod_entry}->get();
			if ($mod_value =~ /^[\+-]?\d+$/) {
				update_display($skills{$skill}, $mod_value, $skills_fields{$skill}{entry});
				$skill_mods{$skill} = $mod_value;
				if($skill eq "Kämpfen" || $skill eq "Ausweichen")
				{
					update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis,	$parademod_entry, $paradegs_entry);
				}
			}
		});
		my $increase_button = $dialog->Button(
			-text => "+",
			-command => sub {
				if($xp_unused_entry->cget('-text') == 0)
				{
					$dialog->messageBox(
					-type    => 'Ok',
					-icon    => 'error',
					-title   => 'Nicht genug XP',
					-message => "Nicht genug freie Erfahrungspunkte!"
					);
					return;
				}

				my $current_skill_value_str = $skills{$skill};
				my $new_skill_value_str;

				# Nächsten Fertigkeitswert bestimmen
				if ($current_skill_value_str =~ /^(\d+)$/) {
					my $number = $1;
					if ($number == 0) { $new_skill_value_str = 4; }
					elsif ($number < 12) { $new_skill_value_str = $number + 2; }
					else { $new_skill_value_str = "12+1"; }
				} elsif ($current_skill_value_str =~ /^12\+(\d+)$/) {
					$new_skill_value_str = "12+" . ($1 + 1);
				}
				
				# Kosten bestimmen
				my $cost = 1;
				my $linked_attribute = $char_skill_attributes{$skill};
				my $attribute_value_str = $attributes{$linked_attribute};

				# Numerische Werte für den Vergleich
				my $numeric_new_skill = ($new_skill_value_str =~ /^12\+(\d+)$/) ? 12 + $1 : $new_skill_value_str;
				my $numeric_attribute = ($attribute_value_str =~ /^12\+(\d+)$/) ? 12 + $1 : $attribute_value_str;
				
				if ($numeric_new_skill > $numeric_attribute) {
					$cost = 2;
				}
				# Das Kaufen einer neuen Fertigkeit (auf W4) kostet immer 1 Punkt
				if ($current_skill_value_str == 0) {
					$cost = 1;
				}

				# Prüfen, ob genug Punkte vorhanden sind
				if ($xp_unused_entry->cget('-text') < $cost) {
					$dialog->messageBox(
						-type    => 'Ok',
						-icon    => 'error',
						-title   => 'Nicht genug XP',
						-message => "Die Steigerung kostet $cost XP, aber es sind nur " . $xp_unused_entry->cget('-text') . " verfügbar."
					);
					return;
				}

				# Änderungen anwenden
				$skills{$skill} = $new_skill_value_str;
				$xp_unused_entry->configure(-text => $xp_unused_entry->cget('-text') - $cost);
				
				update_display($skills{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill);
				if($skill eq "Kämpfen" || $skill eq "Ausweichen")
				{
					update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis,	$parademod_entry, $paradegs_entry);
				}
			}
		)->grid(-row => $row, -column => 1, -sticky => 'n', -ipadx=> 8);

		my $decrease_button = $dialog->Button(
			-text => "-",
			-command => sub {
				my $current_skill_value_str = $skills{$skill};
				return if $current_skill_value_str == 0; # Nichts zu tun

				# Kostenrückerstattung bestimmen
				my $refund = 1;
				my $linked_attribute = $char_skill_attributes{$skill};
				my $attribute_value_str = $attributes{$linked_attribute};
				
				# Numerische Werte für den Vergleich
				my $numeric_current_skill = ($current_skill_value_str =~ /^12\+(\d+)$/) ? 12 + $1 : $current_skill_value_str;
				my $numeric_attribute = ($attribute_value_str =~ /^12\+(\d+)$/) ? 12 + $1 : $attribute_value_str;
				
				if ($numeric_current_skill > $numeric_attribute) {
					$refund = 2;
				}
				# Das Senken von W4 auf 0 gibt immer 1 Punkt zurück
				if ($current_skill_value_str == 4) {
					$refund = 1;
				}
				
				# Vorherigen Fertigkeitswert bestimmen
				my $previous_skill_value_str;
				if ($current_skill_value_str =~ /^12\+(\d+)$/) {
					my $number = $1;
					$previous_skill_value_str = ($number > 1) ? "12+" . ($number - 1) : 12;
				} elsif ($current_skill_value_str =~ /^(\d+)$/) {
					my $number = $1;
					if ($number == 4) { $previous_skill_value_str = 0; }
					elsif ($number > 4) { $previous_skill_value_str = $number - 2; }
				}
				
				# Änderungen anwenden
				$skills{$skill} = $previous_skill_value_str;
				$xp_unused_entry->configure(-text => $xp_unused_entry->cget('-text') + $refund);
				
				update_display($skills{$skill}, $skill_mods{$skill}, $skills_fields{$skill}{entry}, $skill);
				if($skill eq "Kämpfen" || $skill eq "Ausweichen")
				{
					update_parade(\%skills, \%skill_mods, \%attributes, \%attr_mods, $parade_basis,	$parademod_entry, $paradegs_entry);
				}
			}
		)->grid(-row => $row, -column => 1, -sticky => 'e', -ipadx=> 8);

		$row++;
	}

    # Vermögen
    my $vermoegen_label = $dialog->Label(-text => "Vermögen")->grid(-row => $row - 2, -column => 2);
    my $vermoegen_entry = $dialog->Entry(-textvariable => \$current_character->{vermoegen})->grid(-row => $row - 2, -column => 3, -sticky => 'w');

    # Lebensstil
    my $lebensstil_label = $dialog->Label(-text => "Lebensstil")->grid(-row => $row - 1, -column => 2);
    my $lebensstil_entry = $dialog->Entry(-textvariable => \$current_character->{lebensstil})->grid(-row => $row - 1, -column => 3, -sticky => 'w');

    # Talents
    my $talent_listbox = create_talent_frame($xp_unused_entry, $dialog, $row, $current_character->{talents});

    # VR-Ausrüstung
    my $vr_label = $dialog->Label(-text => "VR-Ausrüstung")->grid(-row => $row, -column => 2);
    $row++;
    my $vr_listbox = $dialog->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->grid(-row => $row, -column => 2, -sticky => 'w');
    $vr_listbox->Subwidget('listbox')->bind('<Enter>', sub{$vr_listbox->Subwidget('listbox')->focus()});
    $vr_listbox->Subwidget('listbox')->bind('<Leave>', sub {$dialog->focus();});

    my $vr_button_frame = $dialog->Frame()->grid(-row => $row, -column => 3, -sticky => 'w');
    $vr_button_frame->Button(
        -text => "+",
        -command => sub { add_vr_item($dialog, $vr_listbox) }
    )->pack(-side => 'top');
    $vr_button_frame->Button(
        -text => "-",
        -command => sub { delete_vr_item($dialog, $vr_listbox) }
    )->pack(-side => 'top');
    $row++;
	foreach my $vr_item (@{$current_character->{vr_ausruestung}}) {
        $vr_listbox->insert('end', $vr_item);
    }

    # Handicaps
    my $handicap_listbox = create_handicap_frame($xp_unused_entry, $dialog, $row, $current_character->{handicaps});
	
	# Gegenstände
    my $items_label = $dialog->Label(-text => "Ausrüstung")->grid(-row => $row, -column => 2);
    $row++;
    my $items_listbox = $dialog->Scrolled(
        'Listbox',
        -scrollbars => 'se',  # Vertical scrollbar
        -height     => 5,
        -width      => 30,
    )->grid(-row => $row, -column => 2, -sticky => 'w');
    $items_listbox->Subwidget('listbox')->bind('<Enter>', sub{$items_listbox->Subwidget('listbox')->focus()});
    $items_listbox->Subwidget('listbox')->bind('<Leave>', sub {$dialog->focus();});

    my $items_button_frame = $dialog->Frame()->grid(-row => $row, -column => 3, -sticky => 'w');
    $items_button_frame->Button(
        -text => "+",
        -command => sub { add_items_item($dialog, $items_listbox, 0, 'Gegenstand') }
    )->pack(-side => 'top');
    $items_button_frame->Button(
        -text => "-",
        -command => sub { delete_items_item($dialog, $items_listbox) }
    )->pack(-side => 'top');
	foreach my $item (@{$current_character->{items}}) {
        $items_listbox->insert('end', $item);
    }
	
    $row+=2;

    # Avatar Management
    my $avatar_frame = $dialog->Frame()->grid(-row => $row, -column => 0, -columnspan => 2, -sticky => 'w');
    $row++;
    manage_avatars($avatar_frame, $current_character->{avatars}, \%attributes, \%attr_mods, \%skills, \%skill_mods);

    # Save Button
    $dialog->Button(
        -text    => "Speichern",
        -command => sub {
            $current_character->{name}        = $name_entry->get();
            $current_character->{location}    = $location_entry->get();
            $current_character->{description} = $description_entry->get();
            $current_character->{vermoegen}  = $vermoegen_entry->get();
            $current_character->{lebensstil} = $lebensstil_entry->get();
            $current_character->{vr_ausruestung} = [$vr_listbox->get(0, 'end')];
			$current_character->{items} = [$items_listbox->get(0, 'end')];
            $current_character->{bennies}    = $bennies_entry->get();
            $current_character->{wunden}     = $wunden_entry->get();
			$current_character->{alter}     = $alter_entry->get();
            $current_character->{benniesmax}    = $benniesmax_entry->get();
            $current_character->{wundenmax}     = $wundenmax_entry->get();
            $current_character->{xp}  = $xp_entry->cget('-text');
			$current_character->{xp_unused}  = $xp_unused_entry->cget('-text');
			$current_character->{verstand_benutzt} = $verstand_benutzt;
            $current_character->{rank}  = $rank_entry->cget('-text');
            $current_character->{bewegungmod} = $bewegungmod_entry->get();
			$current_character->{onlinemod} = $onlinemod_entry->get();
			$current_character->{skills} = { %skills };
			$current_character->{skill_mods} = { %skill_mods };
			$current_character->{attributes} = { %attributes };
			$current_character->{attr_mods} = { %attr_mods };
			$current_character->{wissen} = { %wissen_skills };
			$current_character->{attr_steig} = { %attr_steig };
            $current_character->{parademod}   = $parademod_entry->get();
            $current_character->{robustmod}   = $robustmod_entry->get();
            $current_character->{talents}     = [$talent_listbox->get(0, 'end')];
            $current_character->{handicaps}   = [$handicap_listbox->get(0, 'end')];

            update_character_list();
            $edit_char->destroy();
        }
    )->grid(-row => $row, -column => 1, -sticky => 'w');
}


sub update_item_label {
    my ($form, $part, $label_widget, $panzerwerte) = @_;
    # Holen Sie den aktuellen Text aus dem Label
    my $item_name = $panzerwerte->{$part}{name};
	my $panzerwert = $panzerwerte->{$part}{panzerung};
	my $kvwert = $panzerwerte->{$part}{kv};
	my $gewicht = $panzerwerte->{$part}{gewicht};
	my $kosten = $panzerwerte->{$part}{kosten};
	my $anmerkungen = $panzerwerte->{$part}{anmerkungen};

    my $item_dialog = $form->Toplevel();
	focus_dialog($item_dialog, "$part", $form);
    $item_dialog->geometry("350x180");  # Breite x Höhe in Pixeln
	my $scrolled_area = $item_dialog->Scrolled(
        'Frame',
        -scrollbars => 'osoe'
    )->pack(-fill => 'both', -expand => 1);
    my $dialog = $scrolled_area->Subwidget('scrolled');
	my $description_label = $dialog->Label(-text => "Mehrere an dem Ort getragene Teile durch\nKomma trennen und Panzerungswert aufaddieren.")->grid(-row => 0, -column => 0, -columnspan => 2, -sticky => 'w');
    
    my $name_label = $dialog->Label(-text => "getragen an $part")->grid(-row => 1, -column => 0, -sticky => 'w');
    my $entry = $dialog->Entry(-textvariable => \$item_name)->grid(-row => 1, -column => 1, -sticky => 'w');

    # Fügen Sie ein weiteres Label und Eingabefeld in der Zeile darunter hinzu
    my $panzer_label = $dialog->Label(-text => "Panzerungswert")->grid(-row => 2, -column => 0, -sticky => 'w');
    my $panzer_entry = $dialog->Entry(-textvariable => \$panzerwert)->grid(-row => 2, -column => 1, -sticky => 'w');
	
	if($kvwert != -1)
	{
		my $kv_label = $dialog->Label(-text => "Mindest-KV")->grid(-row => 3, -column => 0, -sticky => 'w');
		my $kv_entry = $dialog->Entry(-textvariable => \$kvwert)->grid(-row => 3, -column => 1, -sticky => 'w');
	}
	
	my $gewicht_label = $dialog->Label(-text => "Gewicht")->grid(-row => 4, -column => 0, -sticky => 'w');
    my $gewicht_entry = $dialog->Entry(-textvariable => \$gewicht)->grid(-row => 4, -column => 1, -sticky => 'w');
	
	my $kosten_label = $dialog->Label(-text => "Kosten")->grid(-row => 5, -column => 0, -sticky => 'w');
    my $kosten_entry = $dialog->Entry(-textvariable => \$kosten)->grid(-row => 5, -column => 1, -sticky => 'w');
	
	my $anmerkungen_label = $dialog->Label(-text => "Anmerkungen")->grid(-row => 6, -column => 0, -sticky => 'w');
    my $anmerkungen_entry = $dialog->Entry(-textvariable => \$anmerkungen)->grid(-row => 6, -column => 1, -sticky => 'w');

    # Fügen Sie OK und Abbrechen Buttons hinzu
    my $button_frame = $dialog->Frame()->grid(-row => 7, -column => 0, -columnspan => 2, -sticky => 'ew');
    my $ok_button = $button_frame->Button(-text => "OK", -command => sub {
        $label_widget->configure(-text => "$item_name, P $panzerwert");
		$panzerwerte->{$part}{name} = $item_name;
		$panzerwerte->{$part}{panzerung} = $panzerwert;
		$panzerwerte->{$part}{kv} = $kvwert;
		$panzerwerte->{$part}{gewicht} = $gewicht;
		$panzerwerte->{$part}{kosten} = $kosten;
		$panzerwerte->{$part}{anmerkungen} = $anmerkungen;
        $label_widget->update;  # Stellen Sie sicher, dass die Änderung angewendet wird
		$form->focus();
        $item_dialog->destroy;
    })->pack(-side => 'left', -padx => 5, -pady => 5);

    my $cancel_button = $button_frame->Button(-text => "Abbrechen", -command => sub {
		$form->focus();
        $item_dialog->destroy;
    })->pack(-side => 'right', -padx => 5, -pady => 5);
}

sub focus_dialog
{
	my ($window_widget, $window_title, $parent_widget) = @_;

    unless (eval { $window_widget->isa('Tk::Widget') } && eval { $parent_widget->isa('Tk::Widget') })
	{
        return;
    }
    $window_widget->title($window_title);
    $window_widget->transient($parent_widget);
    #$window_widget->update_idletasks;
    $window_widget->grab();
	#$window_widget->grab_set();
    $window_widget->focusForce;
}

sub update_weapon_label
{
    my ($form, $part, $label_widget, $waffenwerte) = @_;
    my $item_name = $waffenwerte->{$part}{name};
    my $schaden = $waffenwerte->{$part}{schaden};
    my $mindest_kv = $waffenwerte->{$part}{kv};
    my $reichweite = $waffenwerte->{$part}{rw};
	my $gewicht = $waffenwerte->{$part}{gewicht};
	my $kosten = $waffenwerte->{$part}{kosten};
	my $anmerkungen = $waffenwerte->{$part}{anmerkungen};
	my $pb = $waffenwerte->{$part}{pb};
	my $fr = $waffenwerte->{$part}{fr};
	my $schuss = $waffenwerte->{$part}{schuss};
	my $flaeche = $waffenwerte->{$part}{flaeche};
	my $selected_type = $waffenwerte->{$part}{typ} || 'Nahkampf';

    my $weapon_dialog = $form->Toplevel();
	focus_dialog($weapon_dialog, $part, $form);
	my $scrolled_area = $weapon_dialog->Scrolled(
        'Frame',
        -scrollbars => 'osoe'
    )->pack(-fill => 'both', -expand => 1);
    my $dialog = $scrolled_area->Subwidget('scrolled');

    my $reichweite_label = $dialog->Label(-text => "Reichweite")->grid(-row => 6, -column => 0, -sticky => 'w');
    my $reichweite_entry = $dialog->Entry(-textvariable => \$reichweite)->grid(-row => 6, -column => 1, -sticky => 'w');
	my $pb_label = $dialog->Label(-text => "PB")->grid(-row => 7, -column => 0, -sticky => 'w');
    my $pb_entry = $dialog->Entry(-textvariable => \$pb)->grid(-row => 7, -column => 1, -sticky => 'w');
	my $fr_label = $dialog->Label(-text => "FR")->grid(-row => 8, -column => 0, -sticky => 'w');
    my $fr_entry = $dialog->Entry(-textvariable => \$fr)->grid(-row => 8, -column => 1, -sticky => 'w');
	my $schuss_label = $dialog->Label(-text => "Schuss")->grid(-row => 9, -column => 0, -sticky => 'w');
    my $schuss_entry = $dialog->Entry(-textvariable => \$schuss)->grid(-row => 9, -column => 1, -sticky => 'w');
	my $flaeche_label = $dialog->Label(-text => "Flächenschablone")->grid(-row => 10, -column => 0, -sticky => 'w');
    my $flaeche_entry = $dialog->Entry(-textvariable => \$flaeche)->grid(-row => 10, -column => 1, -sticky => 'w');
	
	if($selected_type eq 'Nahkampf')
	{
		$weapon_dialog->geometry("400x200");  # Breite x Höhe in Pixeln
		$reichweite_label->gridForget();
		$reichweite_entry->gridForget();
		$pb_label->gridForget();
		$pb_entry->gridForget();
		$fr_label->gridForget();
		$fr_entry->gridForget();
		$schuss_label->gridForget();
		$schuss_entry->gridForget();
		$flaeche_label->gridForget();
		$flaeche_entry->gridForget();
	}
	else
	{
		$weapon_dialog->geometry("400x300");
	}

    # Fügen Sie ein Dropdown-Menü hinzu, um zwischen Nahkampf- und Fernkampfwaffe zu wählen
    my $weapon_type_label = $dialog->Label(-text => "Waffentyp")->grid(-row => 0, -column => 0, -sticky => 'w');
    my $weapon_type = $dialog->Optionmenu(
        -options => [qw/Nahkampf Fernkampf/],
        -command => sub {
            my $type = shift;
            if ($type eq 'Nahkampf') {
                $reichweite_label->gridForget();
                $reichweite_entry->gridForget();
				$pb_label->gridForget();
                $pb_entry->gridForget();
				$fr_label->gridForget();
                $fr_entry->gridForget();
				$schuss_label->gridForget();
                $schuss_entry->gridForget();
				$flaeche_label->gridForget();
                $flaeche_entry->gridForget();
				$weapon_dialog->geometry("400x200");
            } elsif ($type eq 'Fernkampf') {
                $reichweite_label->grid(-row => 6, -column => 0, -sticky => 'w');
                $reichweite_entry->grid(-row => 6, -column => 1, -sticky => 'w');
				$pb_label->grid(-row => 7, -column => 0, -sticky => 'w');
                $pb_entry->grid(-row => 7, -column => 1, -sticky => 'w');
				$fr_label->grid(-row => 8, -column => 0, -sticky => 'w');
                $fr_entry->grid(-row => 8, -column => 1, -sticky => 'w');
				$schuss_label->grid(-row => 9, -column => 0, -sticky => 'w');
                $schuss_entry->grid(-row => 9, -column => 1, -sticky => 'w');
				$flaeche_label->grid(-row => 10, -column => 0, -sticky => 'w');
                $flaeche_entry->grid(-row => 10, -column => 1, -sticky => 'w');
				$weapon_dialog->geometry("400x300");
            }
        },
        -variable => \$selected_type
    )->grid(-row => 0, -column => 1, -sticky => 'w');

    # Fügen Sie ein Label mit dem Text "Name" hinzu
    my $name_label = $dialog->Label(-text => "getragen an $part")->grid(-row => 1, -column => 0, -sticky => 'w');

    # Verwenden Sie den aktuellen Text als Standardwert für das Eingabefeld
    my $entry = $dialog->Entry(-textvariable => \$item_name)->grid(-row => 1, -column => 1, -sticky => 'w');

    # Fügen Sie ein weiteres Label und Eingabefeld in der Zeile darunter hinzu
    my $schaden_label = $dialog->Label(-text => "Schaden")->grid(-row => 2, -column => 0, -sticky => 'w');
    my $schaden_entry = $dialog->Entry(-textvariable => \$schaden)->grid(-row => 2, -column => 1, -sticky => 'w');
	
	if($mindest_kv ne "-1")
	{
		my $mindest_kv_label = $dialog->Label(-text => "Mindest-KV")->grid(-row => 3, -column => 0, -sticky => 'w');
		my $mindest_kv_entry = $dialog->Entry(-textvariable => \$mindest_kv)->grid(-row => 3, -column => 1, -sticky => 'w');
	}
	
	my $gewicht_label = $dialog->Label(-text => "Gewicht")->grid(-row => 4, -column => 0, -sticky => 'w');
    my $gewicht_entry = $dialog->Entry(-textvariable => \$gewicht)->grid(-row => 4, -column => 1, -sticky => 'w');
	
	my $kosten_label = $dialog->Label(-text => "Kosten")->grid(-row => 5, -column => 0, -sticky => 'w');
    my $kosten_entry = $dialog->Entry(-textvariable => \$kosten)->grid(-row => 5, -column => 1, -sticky => 'w');
	
	my $anmerkungen_label = $dialog->Label(-text => "Anmerkungen")->grid(-row => 11, -column => 0, -sticky => 'w');
    my $anmerkungen_entry = $dialog->Entry(-textvariable => \$anmerkungen)->grid(-row => 11, -column => 1, -sticky => 'w');

    # Fügen Sie OK und Abbrechen Buttons hinzu
    my $button_frame = $dialog->Frame()->grid(-row => 12, -column => 0, -columnspan => 2, -sticky => 'ew');
    my $ok_button = $button_frame->Button(-text => "OK", -command => sub {
        $label_widget->configure(-text => $item_name);
        $waffenwerte->{$part}{name} = $item_name;
        $waffenwerte->{$part}{schaden} = $schaden;
        $waffenwerte->{$part}{kv} = $mindest_kv;
		$waffenwerte->{$part}{kosten} = $kosten;
		$waffenwerte->{$part}{anmerkungen} = $anmerkungen;
		$waffenwerte->{$part}{gewicht} = $gewicht;
		$waffenwerte->{$part}{typ} = $selected_type;
		if($selected_type eq 'Fernkampf')
		{
			$waffenwerte->{$part}{flaeche} = $flaeche;
			$waffenwerte->{$part}{schuss} = $schuss;
			$waffenwerte->{$part}{fr} = $fr;
			$waffenwerte->{$part}{pb} = $pb;
			$waffenwerte->{$part}{rw} = $reichweite;
		}
		else
		{
			$waffenwerte->{$part}{flaeche} = '';
			$waffenwerte->{$part}{schuss} = '';
			$waffenwerte->{$part}{fr} = '';
			$waffenwerte->{$part}{pb} = '';
			$waffenwerte->{$part}{rw} = '';
		}
        $label_widget->update;  # Stellen Sie sicher, dass die Änderung angewendet wird
		$form->focus();
        $weapon_dialog->destroy;
    })->pack(-side => 'left', -padx => 5, -pady => 5);

    my $cancel_button = $button_frame->Button(-text => "Abbrechen", -command => sub {
		$form->focus();
        $weapon_dialog->destroy;
    })->pack(-side => 'right', -padx => 5, -pady => 5);
}


sub add_vr_item {
    my ($dialog, $vr_listbox) = @_;
    my $vr_entry = $dialog->DialogBox(
        -title   => "VR-Ausrüstung hinzufügen",
        -buttons => ["OK", "Abbrechen"],
    );
    $vr_entry->geometry("300x75");
    $vr_entry->add('Label', -text => "VR-Ausrüstung:")->pack();
    my $vr_input = $vr_entry->add('Entry')->pack();
    my $response = $vr_entry->Show();
    if (defined $response && $response eq "OK" && $vr_input->get() ne "") {
        my $new_vr_item = $vr_input->get();

        # Füge den neuen Eintrag zur Listbox hinzu
        $vr_listbox->insert('end', $new_vr_item);

        # Hole alle Einträge aus der Listbox
        my @vr_items = $vr_listbox->get(0, 'end');

        # Sortiere die Einträge alphabetisch
        @vr_items = sort @vr_items;

        # Aktualisiere die Listbox
        $vr_listbox->delete(0, 'end');
        foreach my $vr_item (@vr_items) {
            $vr_listbox->insert('end', $vr_item);
        }

        $dialog->focus();  # Set focus back to dialog
    }
}

sub delete_vr_item {
    my ($dialog, $vr_listbox) = @_;
    my $selected = $vr_listbox->curselection();
    if (defined $selected && @$selected) {
        $vr_listbox->delete($selected->[0]);
    } else {
        # Optional: Fehlermeldung anzeigen
        $mw->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Keine VR-Ausrüstung ausgewählt',
            -message => "Bitte wählen Sie eine VR-Ausrüstung aus, die gelöscht werden soll."
        );
    }
    $dialog->focus();  # Set focus back to dialog
}

sub add_items_item {
    my ($dialog, $items_listbox, $max_items, $type) = @_;
	
	# Überprüfen, ob bereits 10 Gegenstände vorhanden sind
    my @current_items = $items_listbox->get(0, 'end');
    if ($max_items != 0 && @current_items >= $max_items) {
        $dialog->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Maximale Anzahl von Gegenständen erreicht',
            -message => "Sie können maximal 10 Gegenstände hinzufügen."
        );   # Diese Nachricht wird nur bei Gegenständen angezeigt, da $max_items bei Mächten 0 ist.
        return;
    }
    my $items_entry = $dialog->DialogBox(
        -title   => "$type hinzufügen",
        -buttons => ["OK", "Abbrechen"],
    );
    $items_entry->geometry("300x75");
    $items_entry->add('Label', -text => "$type:")->pack();
    my $items_input = $items_entry->add('Entry')->pack();
    my $response = $items_entry->Show();
    if (defined $response && $response eq "OK" && $items_input->get() ne "") {
        my $new_items_item = $items_input->get();

        # Füge den neuen Eintrag zur Listbox hinzu
        $items_listbox->insert('end', $new_items_item);

        # Hole alle Einträge aus der Listbox
        my @items_items = $items_listbox->get(0, 'end');

        # Sortiere die Einträge alphabetisch
        @items_items = sort @items_items;

        # Aktualisiere die Listbox
        $items_listbox->delete(0, 'end');
        foreach my $items_item (@items_items) {
            $items_listbox->insert('end', $items_item);
        }

        $dialog->focus();  # Set focus back to dialog
    }
}

sub delete_items_item
{
    my ($dialog, $items_listbox) = @_;
    my $selected = $items_listbox->curselection();
    if (defined $selected && @$selected) {
        $items_listbox->delete($selected->[0]);
    } else {
        # Optional: Fehlermeldung anzeigen
        $mw->messageBox(
            -type    => 'Ok',
            -icon    => 'info',
            -title   => 'Kein Gegenstand ausgewählt',
            -message => "Bitte wählen Sie einen Gegenstand aus, die gelöscht werden soll."
        );
    }
    $dialog->focus();  # Set focus back to dialog
}

# Hilfsfunktion zum Formatieren von Würfelwerten
sub format_dice {
    my ($value) = @_;
    return 'W0' if !defined $value || $value eq '' || $value eq '0';
    # Akzeptiere "12+X" oder nur Zahlen
    return "W$value" if $value =~ /^\d+$/ || $value =~ /^12\+\d+$/;
	$mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'Würfelwert',
                         -message => "Unerwarteter Würfelwert für format_dice: $value" );
    return "W?"; # Fallback
}

sub draw_page_header {
    my ($pdf, $page, $layout) = @_;

    # --- Logo zeichnen (bleibt oben rechts) ---
    # >> NEU: Variablen hier deklarieren <<
    my $dirname = get_script_dir();
    my $logo_width = 100; # Breite des Logos

    my $logo_path = "$dirname/Uniworld-Logo.png";
    my $logo_height = 0;  # Wird berechnet
    my $logo_y_bottom = $layout->{top_margin} - 50; # Fallback, falls Logo nicht geladen werden kann

    if (-e $logo_path) {
        eval {
            my $logo = $pdf->image_png($logo_path);
            if ($logo) { # Prüfen, ob das Laden erfolgreich war
                # Skalierung des Logos proportional zur Breite
                $logo_height = $logo_width * ($logo->height / $logo->width);
                my $logo_x = $layout->{page_width} - $layout->{right_margin} - $logo_width;
                # Positioniere Logo oben rechts, unterhalb des top_padding
                my $logo_y_top = $layout->{page_height} - $layout->{top_padding};
                my $gfx = $page->gfx;
                # Y für gfx->image ist die untere linke Ecke
                $logo_y_bottom = $logo_y_top - $logo_height;
                $gfx->image($logo, $logo_x, $logo_y_bottom, $logo_width, $logo_height);
            } else {
				$mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF',
                         -message => "Konnte Logo '$logo_path' nicht als PNG-Objekt interpretieren." );
            }
		
        };
		$mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF',
                         -message => "Fehler beim Verarbeiten des Logos '$logo_path': $@" ) if $@;
    } else {
		$mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF',
                         -message => "Logo-Datei nicht gefunden: $logo_path" );
    }
    # Gibt die berechnete oder Fallback-Y-Position zurück
    return $logo_y_bottom;
}

sub check_page_break {
    my ($pdf, $page_ref, $y_pos_ref, $layout, $line_height_needed) = @_;
    $line_height_needed //= $layout->{line_height};

    if ($$y_pos_ref - $line_height_needed < $layout->{bottom_margin}) {
        $$page_ref = $pdf->page();
        $$page_ref->mediabox('A4');
        $$y_pos_ref = $layout->{top_margin};
        draw_page_header($pdf, $$page_ref, $layout); # Logo auf neuer Seite
        return 1;
    }
    return 0;
}

# Schreibt eine einzelne Textzeile, kümmert sich um Font und Seitenumbruch
sub write_pdf_line {
    my (%args) = @_;
    my $pdf         = $args{pdf}        or die "Parameter 'pdf' fehlt";
    my $page_ref    = $args{page_ref}   or die "Parameter 'page_ref' fehlt";
    my $y_pos_ref   = $args{y_pos_ref}  or die "Parameter 'y_pos_ref' fehlt";
    my $layout      = $args{layout}     or die "Parameter 'layout' fehlt";
    my $fonts       = $args{fonts}      or die "Parameter 'fonts' fehlt";
    my $x           = $args{x} // $layout->{left_margin};
    my $text        = defined $args{text} ? $args{text} : '';

    # Optionen
    my $font_style  = $args{font_style} // 'normal';
    my $font_size   = $args{font_size}  // $layout->{font_size};
    my $y_decrement = defined $args{y_decrement} ? $args{y_decrement} : $layout->{line_height};
    my $align       = $args{align} // 'left';
    my $max_width   = $args{max_width} // 0;
    my $v_align     = $args{v_align} // 'baseline'; # Standard bleibt baseline
    my $row_height  = $args{row_height} // $layout->{line_height};

    # Font-Größe sicherstellen
    $font_size = ($layout->{font_size} || 10) if !defined $font_size || $font_size <= 0;
    $font_size = 10 if $font_size <= 0;
    # >> Verwende hier die gleiche Basishöhe wie in draw_table_row <<
    my $font_line_height = $font_size * 1.25; # Angepasst an draw_table_row
    # Textobjekt holen/erstellen
    my $text_obj = $$page_ref->text();
    unless (defined $text_obj) { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "Konnte kein Textobjekt von der Seite holen." ); return 0; }
    # Font setzen
    my $font = $fonts->{$font_style};
    unless (defined $font) { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "FEHLER: Font '$font_style' nicht definiert!" ); return 0; }
    eval { $text_obj->font($font, $font_size); };
    if ($@) { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "FEHLER: Font '$font_style'/$font_size setzen: $@" ); return 0; }

    my @lines_to_draw;
    my $num_lines = 1;

    # --- Zeilenumbruch ---
    if ($max_width > 0 && $text ne '') {
        my $avg_char_width = $font_size * 0.55;
        my $effective_width = $max_width; # Verwende max_width direkt
        $effective_width = 10 if $effective_width < 10;
        my $chars_per_line = int( $effective_width / $avg_char_width ) || 1;
        $chars_per_line = 1 if $chars_per_line < 1;
        local $Text::Wrap::columns = $chars_per_line;
        my $wrapped_text = wrap('', '', $text);
        @lines_to_draw = split '\n', $wrapped_text;
        $num_lines = scalar @lines_to_draw;
    } else {
        @lines_to_draw = ($text);
    }

    # --- Start-Y-Position für die Baseline der ERSTEN Zeile ---
    my $start_y;
    # $$y_pos_ref ist die OBERE Kante der Zelle/Zeile
    if ($v_align eq 'middle') {
        # Vertikaler Mittelpunkt der Zelle - halbe Höhe des *gezeichneten* Textblocks
        my $drawn_text_block_height = $num_lines * $font_line_height;
        my $middle_of_row = $$y_pos_ref - ($row_height / 2);
        $start_y = $middle_of_row + ($drawn_text_block_height / 2) - ($font_size * 0.9); # Baseline der obersten Zeile anpassen
    }
    # >> ELSE für 'top' und 'baseline' <<
    else {
        # Baseline der ersten Zeile knapp unterhalb der oberen Kante
        $start_y = $$y_pos_ref - $font_size * 1.1; # Geringer Abstand nach oben (wie 'top')
    }


    # --- Text Zeile für Zeile zeichnen ---
    my $current_line_y = $start_y;
    foreach my $line (@lines_to_draw) {
        my $y_before_check = $$y_pos_ref;
        check_page_break($pdf, $page_ref, $y_pos_ref, $layout, $font_line_height);
        if ($$y_pos_ref != $y_before_check && $current_line_y != $start_y) {
             $current_line_y = $$y_pos_ref - $font_size * 1.1; # Nach Umbruch oben neu starten
        }

        # X-Position für Alignment
        my $actual_x = $x;
        if ($align ne 'left' && $max_width > 0) {
            eval { $$page_ref->text->font($font, $font_size); };
            my $text_width = $$page_ref->text->text_width($line);
             if ($align eq 'right') { $actual_x = $x + $max_width - $text_width; }
             elsif ($align eq 'center') { $actual_x = $x + ($max_width - $text_width) / 2; }
        }

        # Text positionieren und schreiben
        eval {
            my $current_page_text_obj = $$page_ref->text;
            $current_page_text_obj->font($font, $font_size);
            $current_page_text_obj->translate($actual_x, $current_line_y);
            $current_page_text_obj->text($line);
        };
        if ($@) { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "FEHLER: Font '$font_style'/$font_size setzen: $@" ); }

        $current_line_y -= $font_line_height; # Y für nächste Zeile im Umbruch
    }

    # --- Globale Y-Position dekrementieren (nur wenn explizit gewünscht) ---
    $$y_pos_ref -= $y_decrement if $y_decrement != 0;

    return $num_lines;
}

# Hilfsfunktion zum Hinzufügen einer Überschrift (unverändert)
sub add_pdf_heading {
    my ($pdf, $page_ref, $y_pos_ref, $layout, $fonts, $text, $size) = @_;
    $size //= 14; # Standardgröße für Überschriften
    my $heading_line_height = $size * 1.2;

    check_page_break($pdf, $page_ref, $y_pos_ref, $layout, $heading_line_height * 1.7);
    $$y_pos_ref -= $heading_line_height * 0.5; # Kleiner Abstand vor der Überschrift

    write_pdf_line(
        pdf        => $pdf, page_ref   => $page_ref, y_pos_ref  => $y_pos_ref,
        layout     => $layout, fonts      => $fonts,
        x          => $layout->{left_margin},
        text       => $text, font_style => 'bold', font_size  => $size,
        y_decrement=> $heading_line_height # Y um die Höhe der Überschrift reduzieren
    );
    $$y_pos_ref -= $layout->{line_height} * 0.2; # Kleiner Abstand nach Überschrift

    # Optionale Linie unter der Überschrift (gekürzt)
    my $gfx = $$page_ref->gfx;
    my $line_end_x = $layout->{page_width} - $layout->{right_margin} - 130; # Endpunkt vor Logo-Bereich (100 Logo + 10 Rand + 20 Puffer)
    # Alternative: Fester Wert $layout->{page_width} * 0.7;
    $gfx->save;
    $gfx->linewidth(0.5);
    $gfx->move($layout->{left_margin}, $$y_pos_ref);
    $gfx->line($line_end_x, $$y_pos_ref); # Linie gekürzt
    $gfx->stroke();
    $gfx->restore;
    $$y_pos_ref -= $layout->{line_height} * 0.5; # Zusätzlicher Abstand nach der Linie
}

sub draw_table_row {
    my (%args) = @_;
    my $pdf         = $args{pdf};
    my $page_ref    = $args{page_ref};
    my $y_pos_ref   = $args{y_pos_ref};
    my $layout      = $args{layout};
    my $fonts       = $args{fonts};
    my $row_data    = $args{data};
    my $col_widths  = ref $args{widths} eq 'ARRAY' ? $args{widths} : [];
    my $x_start     = $args{x_start} // $layout->{left_margin};
    my $is_header   = $args{header} // 0;

    # --- Schritt 1: Maximale benötigte Zeilenanzahl ermitteln ---
    my $max_lines_needed = 1;
    my $font_style = $is_header ? 'bold' : 'normal';
    my $font_size = ($layout->{font_size} || 10) - 1;
    $font_size = 9 if $font_size <= 0;
    my $font_obj = $fonts->{$font_style};
    unless (defined $font_obj) { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "FEHLER: Font '$font_style' nicht definiert." ); return; }

    if (ref $col_widths eq 'ARRAY' && @$col_widths > 0) {
        for my $i (0 .. $#$row_data) {
            last unless defined $col_widths->[$i];
            my $cell_text = defined $row_data->[$i] ? $row_data->[$i] : '';
            next if $cell_text eq '';
            my $col_width = $col_widths->[$i];
			my $avg_char_width = $font_size * 0.55; # Schätzung
			my $effective_width = $col_width - 6; # Padding
			$effective_width = 10 if $effective_width < 10;
			my $chars_per_line = int( $effective_width / $avg_char_width ) || 1;
			$chars_per_line = 1 if $chars_per_line < 1;

			local $Text::Wrap::columns = $chars_per_line;
			my $wrapped_text = wrap('', '', $cell_text);
			my $num_lines = ($wrapped_text =~ tr/\n//) + 1;
			$max_lines_needed = $num_lines if $num_lines > $max_lines_needed;
        }
    }

    # --- Schritt 2: Zeilenhöhe berechnen ---
    # >> Basishöhe pro Zeile etwas großzügiger <<
    my $single_line_draw_height = $font_size * 1.3; # Erhöht von 1.2/1.25
    my $text_block_height = $max_lines_needed * $single_line_draw_height;
    my $vertical_padding = 5; # Kleines Padding oben/unten
    my $row_height = $text_block_height + $vertical_padding;
    my $min_row_height = ($layout->{line_height} || 12) * 1.1;
    $row_height = $min_row_height if $row_height < $min_row_height;

    # --- Schritt 3: Seitenumbruch prüfen ---
    check_page_break($pdf, $page_ref, $y_pos_ref, $layout, $row_height);

    # --- Schritt 4: Hintergrund und Rahmen zeichnen (mit der berechneten Höhe) ---
    my $gfx = $$page_ref->gfx;
    # ... (Rahmen- und Hintergrundcode wie zuvor) ...
    my $current_x = $x_start;
    my $total_width = ref $col_widths eq 'ARRAY' ? sum(@$col_widths) : 0;
    my $final_x = $x_start + $total_width;
     if ($is_header) {
        $gfx->save; $gfx->fillcolor('lightgray');
        $gfx->rect($x_start, $$y_pos_ref - $row_height, $final_x - $x_start, $row_height);
        $gfx->fill(); $gfx->restore;
    }
    $gfx->save; $gfx->linewidth(0.5);
    $gfx->move($x_start, $$y_pos_ref); $gfx->line($final_x, $$y_pos_ref);
    $gfx->move($x_start, $$y_pos_ref - $row_height); $gfx->line($final_x, $$y_pos_ref - $row_height);
    my $line_x = $x_start;
    if (ref $col_widths eq 'ARRAY'){
        for my $i (0 .. $#$col_widths) {
             $gfx->move($line_x, $$y_pos_ref); $gfx->line($line_x, $$y_pos_ref - $row_height);
             last unless defined $col_widths->[$i];
             $line_x += $col_widths->[$i];
        }
    }
    $gfx->move($line_x, $$y_pos_ref); $gfx->line($line_x, $$y_pos_ref - $row_height);
    $gfx->stroke(); $gfx->restore;

    # --- Schritt 5: Text für jede Zelle schreiben ---
    $current_x = $x_start;
    my $text_padding = 3;
    if (ref $col_widths eq 'ARRAY' && @$col_widths > 0) {
        for my $i (0 .. $#$row_data) {
            last unless defined $col_widths->[$i];
            my $col_width = $col_widths->[$i];
            my $cell_text = defined $row_data->[$i] ? $row_data->[$i] : '';
            # >> Vertikale Ausrichtung jetzt fix auf 'top' gesetzt <<
            my $v_align_cell = 'top';

            # Rufe write_pdf_line auf
            write_pdf_line(
                pdf => $pdf, page_ref => $page_ref, y_pos_ref => $y_pos_ref,
                layout => $layout, fonts => $fonts,
                x => $current_x + $text_padding, text => $cell_text,
                font_style => $font_style, font_size => $font_size,
                y_decrement => 0,
                max_width => $col_width - (2 * $text_padding),
                v_align => $v_align_cell, # Fix auf 'top'
                row_height => $row_height
            );
            $current_x += $col_width;
        }
    } else { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "WARNUNG: col_widths ungültig in draw_table_row." ); }

    # --- Schritt 6: Globale Y-Position aktualisieren ---
    $$y_pos_ref -= $row_height;
}

sub add_pdf_image {
    my ($pdf, $page_ref, $image_path, $x, $y, $width, $height) = @_;

    my $image_obj;
    eval {
        # Bestimme Typ und lade Bild
        if ($image_path =~ /\.gif$/i) {
            $image_obj = $pdf->image_gif($image_path);
        } elsif ($image_path =~ /\.jpe?g$/i) {
            $image_obj = $pdf->image_jpeg($image_path);
        } elsif ($image_path =~ /\.png$/i) {
            $image_obj = $pdf->image_png($image_path);
        } elsif ($image_path =~ /\.tif?f$/i) {
             $image_obj = $pdf->image_tiff($image_path);
        } else {
            $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "Unbekanntes Bildformat für: $image_path" );
            return;
        }
    };
    if ($@ || !defined $image_obj) {
        $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "Fehler beim Laden des Bildes '$image_path': $@" );
        return;
    }

    # Grafikobjekt holen und Bild platzieren
    my $gfx = $$page_ref->gfx;
    eval {
        # Skaliere proportional, wenn nur eine Dimension gegeben ist
        # (Hier wird angenommen, dass Breite und Höhe übergeben werden)
        $gfx->image($image_obj, $x, $y - $height, $width, $height); # Y ist untere linke Ecke
    };
    if ($@) {
         $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "Fehler beim Platzieren des Bildes '$image_path': $@" );
    }
}

sub draw_checkboxes {
    my (%args) = @_;
    my $pdf         = $args{pdf}        or die "Parameter 'pdf' fehlt";
    my $page_ref    = $args{page_ref}   or die "Parameter 'page_ref' fehlt";
    my $y_pos_ref   = $args{y_pos_ref}  or die "Parameter 'y_pos_ref' fehlt";
    my $layout      = $args{layout}     or die "Parameter 'layout' fehlt";
    my $fonts       = $args{fonts}      or die "Parameter 'fonts' fehlt";
    my $x           = $args{x}          or die "Parameter 'x' fehlt";
    my $label_text  = $args{label}      or die "Parameter 'label' fehlt";
    my $current     = $args{current} // 0;
    my $max         = $args{max}     // 0;
    my $fill_left   = $args{fill_left} // 1;

    return $$y_pos_ref unless $max > 0;

    my $box_size    = $args{box_size} // 8;
    my $spacing     = $args{spacing}  // 2;
    my $label_width = $args{label_width} // 50;
    my $font_style  = 'normal';
    my $font_size   = $layout->{font_size} || 10;

    # Höhe bestimmen (Maximum aus Labelhöhe und Boxhöhe)
    my $label_height = $font_size * 1.2;
    my $row_height = ($label_height > $box_size ? $label_height : $box_size) + 2; # +2 für kleinen Puffer

    check_page_break($pdf, $page_ref, $y_pos_ref, $layout, $row_height);

    my $gfx = $$page_ref->gfx;
    my $text_obj = $$page_ref->text();
    my $font = $fonts->{$font_style};
    unless ($font) { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "Font '$font_style' nicht gefunden!" ); return $$y_pos_ref; }
    eval { $text_obj->font($font, $font_size); };
    if ($@) { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "Font setzen fehlgeschlagen: $@" ); return $$y_pos_ref; }

    # --- Y-Positionen berechnen ---
    # $$y_pos_ref ist die OBERKANTE der logischen Zeile
    my $box_y_bottom = $$y_pos_ref - $row_height; # Untere Kante der Zeile
    my $box_y_top = $$y_pos_ref - ($row_height - $box_size) / 2 - $box_size; # Vertikal zentriert
    # Baseline für den Label-Text, etwa auf Höhe der Box-Unterkante
    my $label_baseline_y = $box_y_top + $font_size * 0.2; # Leicht über der Unterkante der Box

    # 1. Label zeichnen
    eval {
        $text_obj->translate($x, $label_baseline_y);
        $text_obj->text($label_text);
    };
    if ($@) { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "Fehler beim Schreiben des Checkbox-Labels '$label_text': $@" ); }


    # 2. Kästchen zeichnen
    my $box_start_x = $x + $label_width;
    my $num_filled = $fill_left ? $current : ($max - $current);
    $num_filled = 0 if $num_filled < 0;
    $num_filled = $max if $num_filled > $max;

    $gfx->save;
    $gfx->linewidth(0.5);
    for my $i (0 .. $max - 1) {
        my $current_box_x = $box_start_x + $i * ($box_size + $spacing);
        # Leeres Kästchen zeichnen (Y ist die untere linke Ecke)
        $gfx->rect($current_box_x, $box_y_top, $box_size, $box_size);

        # 'X' zeichnen, wenn nötig
        my $draw_x = ($fill_left && $i < $num_filled) || (!$fill_left && $i >= ($max - $num_filled));
        if ($draw_x) {
            my $padding = 1.5;
            $gfx->move($current_box_x + $padding, $box_y_top + $padding);
            $gfx->line($current_box_x + $box_size - $padding, $box_y_top + $box_size - $padding);
            $gfx->move($current_box_x + $padding, $box_y_top + $box_size - $padding);
            $gfx->line($current_box_x + $box_size - $padding, $box_y_top + $padding);
        }
    }
    $gfx->stroke();
    $gfx->restore;

    # Y-Position für die nächste Zeile aktualisieren
    $$y_pos_ref -= $row_height;

    return $$y_pos_ref;
}

# --- Funktion zum Hinzufügen des Hauptcharakters (Refaktorisiert, Referenzübergabe, VR verschoben) ---
sub add_character_to_pdf {
    my ($pdf, $char, $fonts, $layout) = @_;
    my $page = $pdf->page();
    $page->mediabox('A4');
    my $page_ref = \$page;

    my $logo_y_bottom = draw_page_header($pdf, $page, $layout);

    # --- Oberer Block Links ---
    my $y_left = $layout->{top_margin};
    my $x_left = $layout->{left_margin};
	my @widths_char_left = (300, 110); # Breite für Anmerkungen
	draw_table_row(
            pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
            layout       => $layout, fonts       => $fonts, x_start     => $x_left,
            data         => ["Name: ".($char->{name}//''), "Erfahrung: ".($char->{xp}//0)." (Über: ".($char->{xp_unused}//0).")"],
            widths       => \@widths_char_left
        );

	draw_table_row(
		pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
		layout       => $layout, fonts       => $fonts, x_start     => $x_left,
		data         => ["Wohnort: ".($char->{location}//''), "Rang: ".($char->{rank}//'Anfänger')],
		widths       => \@widths_char_left
	);
	draw_table_row(
		pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
		layout       => $layout, fonts       => $fonts, x_start     => $x_left,
		data         => ["Beschreibung: ".($char->{description}//''), "Vermögen: ".($char->{vermoegen}//0)],
		widths       => \@widths_char_left
	);
	draw_table_row(
		pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
		layout       => $layout, fonts       => $fonts, x_start     => $x_left,
		data         => ["Alter: ".($char->{alter}//''), ''],
		widths       => \@widths_char_left
	);
	
    draw_list_section("Handicaps:", $char->{handicaps}, $pdf, $page_ref, \$y_left, $layout, $fonts, $x_left);
    draw_list_section("Talente:", $char->{talents}, $pdf, $page_ref, \$y_left, $layout, $fonts, $x_left);


    # --- Oberer Block Rechts ---
    my $y_right = $layout->{top_margin};
    my $x_right = $layout->{page_width} / 2 + 20;

    $y_right -= $layout->{line_height} * 0.5;

    # --- Bennies und Wunden (unter Logo) ---
    my $y_checkboxes = $logo_y_bottom - $layout->{line_height} * 0.5;
    my $x_checkboxes = $layout->{page_width} - $layout->{right_margin} - 100;
    # ... (Code für draw_checkboxes) ...
    draw_checkboxes( pdf => $pdf, page_ref => $page_ref, y_pos_ref => \$y_checkboxes, layout => $layout, fonts => $fonts, x => $x_checkboxes, label => "Bennies: ", current => $char->{bennies}//0, max => $char->{benniesmax}//0, fill_left => 0, label_width => 50 );
    draw_checkboxes( pdf => $pdf, page_ref => $page_ref, y_pos_ref => \$y_checkboxes, layout => $layout, fonts => $fonts, x => $x_checkboxes, label => "Wunden: ", current => $char->{wunden}//0, max => $char->{wundenmax}//0, fill_left => 1, label_width => 50 );

    # --- Start Y-Position für die unteren Blöcke ---
    my $table_start_y = ($y_left < $y_right ? $y_left : $y_right);
    $table_start_y -= $layout->{line_height} * 2.0;


    # --- Linke untere Spalte (enthält jetzt ALLES darunter) ---
    my $y_lower_left = $table_start_y;
    my $x_lower_left = $layout->{left_margin};

    # Attribute Tabelle
    add_pdf_heading($pdf, $page_ref, \$y_lower_left, $layout, $fonts, "Attribute", 12);
    my @attr_widths = (150, 40, 40, 150);
    # ... (Code zum Füllen der Attribute-Tabelle) ...
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['Attribut', 'Wert', 'Mod', 'Gesamt'], widths => \@attr_widths, header => 1);
    foreach my $attr_name (@char_attributes) {
        my $attr_val = $char->{attributes}{$attr_name} // 4;
        my $attr_mod = $char->{attr_mods}{$attr_name} // 0;
        my $display_val = format_dice($attr_val);
        my $display_mod = ($attr_mod > 0 ? "+$attr_mod" : ($attr_mod < 0 ? $attr_mod : "0"));
		my $gesamt = $display_val;
		if($display_val =~ /W12\+(\d+)$/)
		{
			my $value = $1 + $attr_mod;
			if($value > 0)
			{
				$gesamt = "W12+$value";
			}
			else
			{
				$gesamt = "W12$value";
			}
		}
		else
		{
			$gesamt = "$display_val$display_mod" if($display_mod ne 0);
		}
        draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => [$attr_name, $display_val, $display_mod, $gesamt], widths => \@attr_widths);
    }
    $y_lower_left -= $layout->{line_height};

    # Fertigkeiten Tabelle
    add_pdf_heading($pdf, $page_ref, \$y_lower_left, $layout, $fonts, "Fertigkeiten", 12);
    my @skill_widths = (150, 40, 40, 150);
    # ... (Code zum Füllen der Fertigkeiten-Tabelle inkl. Wissen) ...
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['Fertigkeit', 'Wert', 'Mod', 'Gesamt'], widths => \@skill_widths, header => 1);
    foreach my $skill_name (@char_skills) {
        my $skill_val = $char->{skills}{$skill_name} // 0;
        my $skill_mod = $char->{skill_mods}{$skill_name} // 0;
        my $display_val = format_dice($skill_val);
        my $display_mod = ($skill_mod > 0 ? "+$skill_mod" : ($skill_mod < 0 ? $skill_mod : "0"));
		my $gesamt = $display_val;
		if($display_val =~ /W12\+(\d+)$/)
		{
			my $value = $1 + $skill_mod;
			if($value > 0)
			{
				$gesamt = "W12+$value";
			}
			else
			{
				$gesamt = "W12$value";
			}
		}
		else
		{
			$gesamt = "$display_val$display_mod" if($display_mod ne 0);
		}
        draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => [$skill_name, $display_val, $display_mod, $gesamt], widths => \@skill_widths);
    }
     if (exists $char->{wissen} && ref $char->{wissen} eq 'HASH') {
        foreach my $wissen_name (sort keys %{$char->{wissen}}) {
             my $wissen_val = $char->{wissen}{$wissen_name} // 0;
             next if $wissen_val eq '0' || $wissen_val eq 0;
             my $display_val = format_dice($wissen_val);
             draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ["Wissen ($wissen_name)", $display_val, 0, $display_val], widths => \@skill_widths);
        }
    }
    $y_lower_left -= $layout->{line_height};

    # Abgeleitete Werte Tabelle
    add_pdf_heading($pdf, $page_ref, \$y_lower_left, $layout, $fonts, "Abgeleitete Werte", 12);
    my @derived_widths = (100, 50, 50, 50);
    # ... (Berechnungen und Füllen der Tabelle) ...
    my %dummy_skills = %{$char->{skills}}; my %dummy_skill_mods = %{$char->{skill_mods} // {}};
    my %dummy_attributes = %{$char->{attributes}}; my %dummy_attr_mods = %{$char->{attr_mods} // {}};
    my $kampf_val = ($dummy_skills{'Kämpfen'} // 0); $kampf_val = 12+$1 if $kampf_val=~/^12\+(\d+)$/; $kampf_val += ($dummy_skill_mods{'Kämpfen'} // 0);
    my $reaktion_val = ($dummy_attributes{'Reaktion'} // 4); $reaktion_val = 12+$1 if $reaktion_val=~/^12\+(\d+)$/; $reaktion_val += ($dummy_attr_mods{'Reaktion'} // 0);
    my $ausw_val = ($dummy_skills{'Ausweichen'} // 0); $ausw_val = 12+$1 if $ausw_val=~/^12\+(\d+)$/; $ausw_val += ($dummy_skill_mods{'Ausweichen'} // 0);
    my $kv_val = ($dummy_attributes{'Körperliche Verfassung'} // 4); $kv_val = $1 + $2 if($kv_val =~ /^(\d+)\+(\d+)/);
    my $parade_basis_val = ceil(2 + ($kampf_val/2) + ($reaktion_val/4) + ($ausw_val/2));
	my $robust_basis_val = ceil(2 + ($kv_val / 2) + ($dummy_attr_mods{'Körperliche Verfassung'} || 0));
    my $online_basis_val = ($kv_val + ($dummy_attr_mods{'Körperliche Verfassung'} || 0)) / 2;
	my $online_gesamt = $online_basis_val + ($char->{onlinemod} // 0);
	$online_basis_val =~ s/\./,/;
	$online_gesamt =~ s/\./,/;
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['Wert', 'Basis', 'Mod', 'Gesamt'], widths => \@derived_widths, header => 1);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['Bewegung', 6, ($char->{bewegungmod} // 0), (6 + ($char->{bewegungmod} // 0)) . '"'], widths => \@derived_widths);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['Parade', $parade_basis_val, ($char->{parademod} // 0), ($parade_basis_val + ($char->{parademod} // 0))], widths => \@derived_widths);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['Robustheit', $robust_basis_val, ($char->{robustmod} // 0), ($robust_basis_val + ($char->{robustmod} // 0))], widths => \@derived_widths);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['Online-Zeit', "$online_basis_val h", ($char->{onlinemod} // 0), "$online_gesamt h"], widths => \@derived_widths);
    $y_lower_left -= $layout->{line_height};

    # Avatare Tabelle
    add_pdf_heading($pdf, $page_ref, \$y_lower_left, $layout, $fonts, "Avatare", 12);
    my @avatar_list_widths = (100, 100);
    # ... (Code zum Füllen der Avatare-Tabelle) ...
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['Avatar', 'Spielwelt'], widths => \@avatar_list_widths, header => 1);
    my $avs = $char->{avatars} // [];
    foreach my $av (@$avs) {
        next unless ref $av eq 'HASH';
        draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => [$av->{name}//'?', $av->{game}//'?'], widths => \@avatar_list_widths);
    }
    my $num_avatars_drawn = scalar @$avs;
    for (my $i = $num_avatars_drawn; $i < 3; $i++) {
        draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left, data => ['', ''], widths => \@avatar_list_widths);
    }
    $y_lower_left -= $layout->{line_height};

    # --- Ausrüstung Liste (Links) ---
    draw_list_section("Ausrüstung:", $char->{items}, $pdf, $page_ref, \$y_lower_left, $layout, $fonts, $x_lower_left);

    # --- VR-Ausrüstung Liste (Links) ---
    draw_list_section("VR-Ausrüstung:", $char->{vr_ausruestung}, $pdf, $page_ref, \$y_lower_left, $layout, $fonts, $x_lower_left);

    # --- Panzerung Tabelle (Links) ---
    add_pdf_heading($pdf, $page_ref, \$y_lower_left, $layout, $fonts, "Panzerung", 12);
    my @armor_widths_char_left = (60, 90, 30, 220); # Breite für Anmerkungen
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left,
                   data => ['Ort', 'Name', 'P', 'Anmerkungen'], widths => \@armor_widths_char_left, header => 1);
    foreach my $loc ('Kopf', 'Torso', 'Arme', 'Beine') {
        my $p = (exists $char->{panzer} && ref $char->{panzer} eq 'HASH' && exists $char->{panzer}{$loc}) ? $char->{panzer}{$loc} : {};
        $p = {} unless ref $p eq 'HASH';

        draw_table_row(
            pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_lower_left,
            layout       => $layout, fonts       => $fonts, x_start     => $x_lower_left,
            data         => [$loc, $p->{name} // '', $p->{panzerung} // 0, $p->{anmerkungen} // ''],
            widths       => \@armor_widths_char_left
        );
    }
    $y_lower_left -= $layout->{line_height}; # Abstand
#my @weapon_widths_av_left = (45, 80, 50, 50, 45, 40, 25, 25, 50, 50, 90);
    # --- Waffen Tabelle (Links) ---
    add_pdf_heading($pdf, $page_ref, \$y_lower_left, $layout, $fonts, "Waffen", 12);
    my @weapon_widths_char_left = (45, 70, 48, 48, 42, 30, 40, 25, 25, 48, 50, 80);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left,
                   data => ['Ort', 'Name', 'Schaden', 'Gewicht', 'Kosten', 'KV', 'RW', 'PB', 'FR', 'Schuss', 'FS', 'Anmerkungen'], widths => \@weapon_widths_char_left, header => 1);
    foreach my $loc ('linke Hand', 'rechte Hand') {
        my $w = (exists $char->{waffen} && ref $char->{waffen} eq 'HASH' && exists $char->{waffen}{$loc}) ? $char->{waffen}{$loc} : {};
        $w = {} unless ref $w eq 'HASH';

        draw_table_row(
            pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_lower_left,
            layout       => $layout, fonts       => $fonts, x_start     => $x_lower_left,
            data         => [$loc, $w->{name} // 'Nichts', $w->{schaden} // '-', $w->{gewicht} // '-', $w->{kosten} // '-', $w->{kv} // '-', $w->{rw} // '-', $w->{pb} // '-', $w->{fr} // '-', $w->{schuss} // '-', $w->{flaeche} // '-', $w->{anmerkungen} // ''],
            widths       => \@weapon_widths_char_left
        );
    }
	draw_table_row( # Leerzeile
        pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_lower_left,
        layout       => $layout, fonts       => $fonts, x_start     => $x_lower_left,
        data         => [ ('') x 11 ],
        widths       => \@weapon_widths_char_left
    );


    # --- Rechte untere Spalte bleibt leer ---


    # --- Finalen Y-Punkt bestimmen und zurückgeben ---
    # Nimm die finale Y-Position der linken Spalte
    my $final_y = $y_lower_left;

    return ($page, $final_y);
}

# --- Funktion zum Hinzufügen eines Avatars (Angepasst an Charakter-Layout) ---
sub add_avatar_to_pdf {
    my ($pdf, $avatar, $page, $y_pos, $fonts, $layout) = @_;

    my $page_ref = \$page;
    my $y_pos_ref = \$y_pos;

    # --- Seitenumbruch prüfen / Neue Seite beginnen ---
    check_page_break($pdf, $page_ref, $y_pos_ref, $layout, 100);

    # >> Header (Logo) zeichnen und Y-Position holen <<
    my $logo_y_bottom = draw_page_header($pdf, $$page_ref, $layout);

    # --- Avatar Überschrift ---
    add_pdf_heading($pdf, $page_ref, $y_pos_ref, $layout, $fonts,
        "Avatar: " . ($avatar->{name} // 'Unbenannt') . " [" . ($avatar->{game}//'') . "]", 14);

    # --- Oberer Block Links ---
    my $y_left = $$y_pos_ref;
    my $x_left = $layout->{left_margin};
	if(defined $avatar->{main})
	{
		my @widths_ava_left = (410);
		draw_table_row(
		pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
		layout       => $layout, fonts       => $fonts, x_start     => $x_left,
		data         => ["Name: ".($avatar->{name}//'')],
		widths       => \@widths_ava_left
		);

		draw_table_row(
			pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
			layout       => $layout, fonts       => $fonts, x_start     => $x_left,
			data         => ["Welt: $avatar->{game}"],
			widths       => \@widths_ava_left
		);
		draw_table_row(
			pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
			layout       => $layout, fonts       => $fonts, x_start     => $x_left,
			data         => ["Beschreibung: ".($avatar->{description}//'')],
			widths       => \@widths_ava_left
		);
	}
	else
	{
		my @widths_ava_left = (300, 110);
		draw_table_row(
			pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
			layout       => $layout, fonts       => $fonts, x_start     => $x_left,
			data         => ["Name: ".($avatar->{name}//''), "Level: ".$avatar->{level}],
			widths       => \@widths_ava_left
		);

		draw_table_row(
			pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
			layout       => $layout, fonts       => $fonts, x_start     => $x_left,
			data         => ["Welt: ".($avatar->{game}//''), "Rang: ".$avatar->{rank}],
			widths       => \@widths_ava_left
		);
		draw_table_row(
			pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
			layout       => $layout, fonts       => $fonts, x_start     => $x_left,
			data         => ["Beschreibung: ".($avatar->{description}//''), "XP: ".$avatar->{xp}],
			widths       => \@widths_ava_left
		);
		draw_table_row(
			pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
			layout       => $layout, fonts       => $fonts, x_start     => $x_left,
			data         => ["Gildenzugehörigkeit: ".($avatar->{gilden}//'Keine'), "Steigerungspunkte: $avatar->{steigerungspunkte}"],
			widths       => \@widths_ava_left
		);
		draw_table_row(
			pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_left,
			layout       => $layout, fonts       => $fonts, x_start     => $x_left,
			data         => ["Vermögen: ".($avatar->{vermoegen}//0), "Inventarslots: $avatar->{inventarslots}"],
			widths       => \@widths_ava_left
		);
	}
    $y_left -= $layout->{line_height} * 0.5;
	
	return ($$page_ref, $y_left) if(defined $avatar->{main}); # Haupt-Avatar wurde geschrieben
    # Listen Links (Handicaps, Talente)
    draw_list_section("Handicaps:", $avatar->{handicaps}, $pdf, $page_ref, \$y_left, $layout, $fonts, $x_left);
    draw_list_section("Talente:", $avatar->{talents}, $pdf, $page_ref, \$y_left, $layout, $fonts, $x_left);

    # --- Oberer Block Rechts ---
    my $y_right = $$y_pos_ref; # Startet auf gleicher Höhe nach Überschrift
    my $x_right = $layout->{page_width} / 2 + 20;

    $y_right -= $layout->{line_height} * 0.5;


    # --- Bennies und Wunden (unter Logo) ---
    my $y_checkboxes = $logo_y_bottom - $layout->{line_height} * 0.5;
    my $x_checkboxes = $layout->{page_width} - $layout->{right_margin} - 100;
    # Bennies
    draw_checkboxes(
        pdf => $pdf, page_ref => $page_ref, y_pos_ref => \$y_checkboxes, layout => $layout, fonts => $fonts,
        x => $x_checkboxes, label => "Bennies: ", current => $avatar->{bennies}//0, max => $avatar->{benniesmax}//0,
        fill_left => 0, label_width => 50
    );
    # Wunden
    draw_checkboxes(
        pdf => $pdf, page_ref => $page_ref, y_pos_ref => \$y_checkboxes, layout => $layout, fonts => $fonts,
        x => $x_checkboxes, label => "Wunden: ", current => $avatar->{wunden}//0, max => $avatar->{wundenmax}//0,
        fill_left => 1, label_width => 50
    );
	write_pdf_line(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_checkboxes, layout=>$layout, fonts=>$fonts, x=>$x_checkboxes, text=>"Tägliche Heiltränke: $avatar->{heiltrank}");
	write_pdf_line(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_checkboxes, layout=>$layout, fonts=>$fonts, x=>$x_checkboxes, text=>"Tägliche Machttränke: $avatar->{machttrank}");

    # --- Start Y für untere Tabellen ---
    my $lower_start_y_av = ($y_left < $y_right ? $y_left : $y_right);
    $lower_start_y_av -= $layout->{line_height} * 2.0; # Mehr Abstand


    # --- Linke untere Spalte (Avatar) ---
    my $y_lower_left_av = $lower_start_y_av;
    my $x_lower_left_av = $layout->{left_margin};

    # --- Avatar-Fertigkeiten Tabelle (Links) ---
    add_pdf_heading($pdf, $page_ref, \$y_lower_left_av, $layout, $fonts, "Fertigkeiten (Avatar)", 12);
    my @skill_widths_av = (150, 40, 40, 150);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av,
                   data => ['Fertigkeit', 'Wert', 'Mod', 'Gesamt'], widths => \@skill_widths_av, header => 1);
    foreach my $skill_name (@avatar_skills) { # Verwende @avatar_skills
        my $skill_val = $avatar->{skills}{$skill_name} // 0;
        my $skill_mod = $avatar->{skill_mods}{$skill_name} // 0;
        my $display_val = format_dice($skill_val);
        my $display_mod = ($skill_mod > 0 ? "+$skill_mod" : $skill_mod < 0 ? "$skill_mod" : "0");
		my $gesamt = $display_val;
		if($display_val =~ /W12\+(\d+)$/)
		{
			my $value = $1 + $skill_mod;
			if($value > 0)
			{
				$gesamt = "W12+$value";
			}
			else
			{
				$gesamt = "W12$value";
			}
		}
		else
		{
			$gesamt = "$display_val$display_mod" if($display_mod ne 0);
		}
        draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av,
                        data => [$skill_name, $display_val, $display_mod, $gesamt], widths => \@skill_widths_av);
    }
	if (exists $avatar->{wissen} && ref $avatar->{wissen} eq 'HASH') {
        foreach my $wissen_name (sort keys %{$avatar->{wissen}}) {
             my $wissen_val = $avatar->{wissen}{$wissen_name} // 0;
             next if $wissen_val eq '0' || $wissen_val eq 0;
             my $display_val = format_dice($wissen_val);
             draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av, data => ["Wissen ($wissen_name)", $display_val, 0, $display_val], widths => \@skill_widths_av);
        }
    }
    $y_lower_left_av -= $layout->{line_height};
	
	  # --- Abgeleitete Werte (Avatar, Rechte Spalte) ---
    add_pdf_heading($pdf, $page_ref, \$y_lower_left_av, $layout, $fonts, "Abgeleitete Werte", 12);
    my @derived_widths_av2 = (100, 50, 50, 50);
    # Werte holen und berechnen
    my $parade_mod_av = $avatar->{parademod} // 0;
    my $robust_mod_av = $avatar->{robustmod} // 0;
    my $bewegung_mod_av = $avatar->{bewegungmod} // 0;
    my $nahkampf_val_av = $avatar->{skills}{'Nahkampf'} // 0; $nahkampf_val_av = 12+$1 if $nahkampf_val_av =~ /^12\+(\d+)$/;
    my $nahkampf_mod_av = $avatar->{skill_mods}{'Nahkampf'} // 0;
    my $konst_val_av = $avatar->{skills}{'Konstitution'} // 0; $konst_val_av = 12+$1 if $konst_val_av =~ /^12\+(\d+)$/;
    my $konst_mod_av = $avatar->{skill_mods}{'Konstitution'} // 0;
    my $parade_basis_av = ceil(2 + (($nahkampf_val_av + $nahkampf_mod_av) / 2));
    my $robust_basis_av = ceil(2 + (($konst_val_av + $konst_mod_av) / 2));

    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av, data => ['Wert', 'Basis', 'Mod', 'Gesamt'], widths => \@derived_widths_av2, header => 1);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av, data => ['Bewegung', 6, $bewegung_mod_av, (6 + $bewegung_mod_av).'"'], widths => \@derived_widths_av2);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av, data => ['Parade', $parade_basis_av, $parade_mod_av, ($parade_basis_av + $parade_mod_av)], widths => \@derived_widths_av2);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av, data => ['Robustheit', $robust_basis_av, $robust_mod_av, ($robust_basis_av + $robust_mod_av)], widths => \@derived_widths_av2);
    $y_lower_left_av -= $layout->{line_height}; # Abstand

    # --- Panzerung Tabelle (Links unten) ---
    add_pdf_heading($pdf, $page_ref, \$y_lower_left_av, $layout, $fonts, "Panzerung", 12);
    my @armor_widths_av_left = (60, 90, 30, 220);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av, data => ['Ort', 'Name', 'P', 'Anmerkungen'], widths => \@armor_widths_av_left, header => 1);
    foreach my $loc ('Kopf', 'Torso', 'Arme', 'Beine') {
         my $p = $avatar->{panzer}{$loc} // {};
         $p = {} unless ref $p eq 'HASH';
         draw_table_row(
            pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_lower_left_av,
            layout       => $layout, fonts       => $fonts, x_start     => $x_lower_left_av,
            data         => [$loc, $p->{name}//'', $p->{panzerung}//0, $p->{anmerkungen}//''],
            widths       => \@armor_widths_av_left
         );
    }
    $y_lower_left_av -= $layout->{line_height};

    # --- Waffen Tabelle (Links unten) ---
    add_pdf_heading($pdf, $page_ref, \$y_lower_left_av, $layout, $fonts, "Waffen", 12);
    my @weapon_widths_av_left = (45, 80, 50, 50, 45, 40, 25, 25, 50, 50, 90);
    draw_table_row(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x_start=>$x_lower_left_av, data => ['Ort', 'Name', 'Schaden', 'Gewicht', 'Kosten', 'RW', 'PB', 'FR', 'Schuss', 'FS', 'Anmerkungen'], widths => \@weapon_widths_av_left, header => 1);
    foreach my $loc ('linke Hand', 'rechte Hand') {
         my $w = $avatar->{waffen}{$loc} // {};
         $w = {} unless ref $w eq 'HASH';
         my @w_data = ($loc, $w->{name}//'Nichts', $w->{schaden}//'-', $w->{gewicht}//'-', $w->{kosten}//'-', $w->{rw}//'-');
         if ($w->{typ} && $w->{typ} eq 'Fernkampf') { push @w_data, $w->{pb}//1, $w->{fr}//1, $w->{schuss}//0, $w->{flaeche}//'-'; }
         else { push @w_data, '-', '-', '-', '-'; } # Platzhalter für Nahkampf
         push @w_data, $w->{anmerkungen}//'';
         draw_table_row(
            pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_lower_left_av,
            layout       => $layout, fonts       => $fonts, x_start     => $x_lower_left_av,
            data         => \@w_data,
            widths       => \@weapon_widths_av_left
         );
    }
    draw_table_row( # Leerzeile
        pdf          => $pdf, page_ref    => $page_ref, y_pos_ref   => \$y_lower_left_av,
        layout       => $layout, fonts       => $fonts, x_start     => $x_lower_left_av,
        data         => [ ('') x 10 ],
        widths       => \@weapon_widths_av_left
    );
    # $y_lower_left_av -= $layout->{line_height}; # Kein Abstand nach letztem Element links


    # --- Rechte untere Spalte (Avatar) ---
    my $y_lower_right_av = $lower_start_y_av; # Startet auf gleicher Höhe
    my $x_lower_right_av = $layout->{page_width} / 2 + 20;


	# --- Mächte ---
    draw_list_section("Ausrüstung:", $avatar->{items}, $pdf, $page_ref, \$y_lower_left_av, $layout, $fonts, $x_lower_left_av);
	
    # --- Mächte ---
    draw_list_section("Mächte:", $avatar->{maechte}, $pdf, $page_ref, \$y_lower_left_av, $layout, $fonts, $x_lower_left_av);

	#  --- Notizen ---
	add_pdf_heading($pdf, $page_ref, \$y_lower_left_av, $layout, $fonts, "Notizen", 12);
	
	my $notes = $avatar->{notizen} // '';
    if ($notes ne '') {
        my $notes_width = $layout->{page_width} - $x_lower_left_av - $layout->{right_margin};
        my @note_lines = split '\n', $notes;
        foreach my $note_line (@note_lines) {
            # Rufe write_pdf_line für jede Zeile der Notizen auf
            # Es wird automatisch umgebrochen, wenn die Zeile zu lang ist
            write_pdf_line(
                pdf => $pdf, page_ref => $page_ref, y_pos_ref => \$y_lower_left_av,
                layout => $layout, fonts => $fonts,
                x => $x_lower_left_av, text => $note_line,
                max_width => $notes_width # Breite der rechten Spalte
            );
        }
    } else {
        write_pdf_line(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>\$y_lower_left_av, layout=>$layout, fonts=>$fonts, x=>$x_lower_left_av, text=>"- Keine -");
    }
    # --- Finalen Y-Punkt bestimmen und zurückgeben ---
    my $final_y_av = ($y_lower_left_av < $y_lower_right_av ? $y_lower_left_av : $y_lower_right_av);

    return ($$page_ref, $final_y_av); # Seite und finale Y-Position zurückgeben
}


sub draw_list_section {
    my ($title, $items_ref, $pdf, $page_ref, $y_ref, $layout, $fonts, $x_start) = @_;

    # Prüfen, ob überhaupt Items da sind
    my @items = @{$items_ref // []};
    add_pdf_heading($pdf, $page_ref, $y_ref, $layout, $fonts, $title, 10);
    return $$y_ref unless @items; # Wenn leer, nur Titel und raus

    foreach my $item (@items) {
        # Prüfe *vorher*, ob genug Platz für mind. eine Zeile ist
        check_page_break($pdf, $page_ref, $y_ref, $layout, $layout->{line_height} * 1.1);

        # Einfacher Zeilenumbruch
        my $max_chars_per_line = 45; # Ggf. anpassen
        # Umbruch nur bei Leerzeichen versuchen für schönere Darstellung
        my @lines;
        my $remaining_text = $item;
        while (length $remaining_text > $max_chars_per_line) {
             my $break_pos = rindex($remaining_text, ' ', $max_chars_per_line);
             if ($break_pos <= 0) { # Kein Leerzeichen gefunden, hart umbrechen
                 $break_pos = $max_chars_per_line;
             }
             push @lines, substr($remaining_text, 0, $break_pos);
             $remaining_text = substr($remaining_text, $break_pos + 1); # +1 um Leerzeichen zu überspringen
             $remaining_text =~ s/^\s+//; # Führende Leerzeichen entfernen
        }
        push @lines, $remaining_text if length $remaining_text > 0;


        my $prefix = "- ";
        foreach my $line (@lines) {
             # Erneuter Check für Folgezeilen nicht schädlich
             check_page_break($pdf, $page_ref, $y_ref, $layout, $layout->{line_height} * 1.1);
             write_pdf_line(pdf=>$pdf, page_ref=>$page_ref, y_pos_ref=>$y_ref, layout=>$layout, fonts=>$fonts, x=>$x_start, text=> $prefix . $line);
             $prefix = "  "; # Einrücken für Folgezeilen
        }
    }
    $$y_ref -= $layout->{line_height};

    return $$y_ref; # Gib die aktualisierte Y-Position zurück
}

# --- HAUPTFUNKTION für den PDF-Export (mit Tk::getSaveFile) ---
sub export_to_pdf {
    unless (defined $current_character) {
        $mw->messageBox( -type => 'Ok', -icon => 'info', -title => 'Charakter wählen',
                         -message => "Bitte zuerst einen Charakter auswählen." );
        return;
    }

    my $default_filename = ($current_character->{name} // 'charakter');
    $default_filename =~ s/[\\\/:\*\?"<>\|]+/_/g;
    $default_filename .= ".pdf";

    my $filename = $mw->getSaveFile(
        -title        => "Charakter als PDF speichern",
        -initialdir   => '.',
        -initialfile  => $default_filename,
        -defaultextension => '.pdf',
        -filetypes    => [ ['PDF Dateien', '.pdf'], ['Alle Dateien', '*'] ]
    );
	return unless(defined $filename);
    $filename .= '.pdf' unless $filename =~ /\.pdf$/i;

    # --- PDF-Erstellung starten ---
    my $pdf;
    eval {
        $pdf = PDF::API2->new();

        # Fonts definieren
        my %fonts = (
            normal => $pdf->corefont('Helvetica', -encoding => 'utf8'),
            bold   => $pdf->corefont('Helvetica-Bold', -encoding => 'utf8'),
        );

        # Layout-Konstanten (in Punkten)
        my %layout = (
            page_width    => 595, # A4 Breite
            page_height   => 842, # A4 Höhe
            top_margin    => 780, # Start Y (hoch, da von oben gezählt)
            bottom_margin => 40,  # Unterer Rand
            left_margin   => 40,  # Linker Rand
            right_margin  => 40,  # Rechter Rand (Abstand vom rechten Seitenrand)
            top_padding   => 30,  # Abstand für Logo von oben
            line_height   => 12,  # Standard Zeilenhöhe
            font_size     => 10,  # Standard Schriftgröße
            # Layout-spezifische X-Positionen können hier auch rein
            # z.B. center_x => 300, right_col => 440
        );

        # --- Hauptcharakter hinzufügen ---
        my ($current_page, $current_y) = add_character_to_pdf($pdf, $current_character, \%fonts, \%layout);

        # --- Avatare hinzufügen ---
        if (exists $current_character->{avatars} && ref $current_character->{avatars} eq 'ARRAY') {
            foreach my $avatar (@{$current_character->{avatars}}) {
                if (ref $avatar eq 'HASH') {
					$current_page = $pdf->page();
					$current_page->mediabox('A4');
					$current_y = $layout{top_margin};
                    # Funktion aufrufen, die aktuelle Seite und Y-Position übernimmt
                    ($current_page, $current_y) = add_avatar_to_pdf($pdf, $avatar, $current_page, $current_y, \%fonts, \%layout);
                } else {
                    $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF', -message => "Ungültiger Avatar-Eintrag gefunden: " . Dumper($avatar) );
                }
            }
        }

        # --- PDF speichern ---
        $pdf->saveas($filename);

    }; # Ende eval

    if ($@) {
        my $error_msg = $@;
        $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'PDF Export Fehler',
                         -message => "Konnte die PDF-Datei $filename nicht erstellen:\n$error_msg" );
    } else {
        $mw->messageBox( -type => 'Ok', -icon => 'info', -title => 'PDF Export erfolgreich',
                         -message => "Charakter wurde erfolgreich als\n'$filename'\ngespeichert." );
    }
}

# Update character listbox
sub update_character_list {
    $listbox->delete(0, 'end');
    foreach my $character (sort { $a->{name} cmp $b->{name} } values %$characters) {
        $listbox->insert('end', $character->{name});
    }
}

# Select character from listbox
sub select_character {
    my @selected = $listbox->curselection();
    return unless @selected;  # Check if an item is selected

    my $index = $selected[0];
    my $name = $listbox->get($index);
    foreach my $character (values %$characters) {
        if ($character->{name} eq $name) {
            $current_character = $character;
            last;
        }
    }
}

sub manage_wissen_skills {
    my ($punktetyp, $parent_dialog, $wissen_skills_ref, $verstand_used_ref, $verstand_max, $skillpunkt_entry) = @_;
	$verstand_max = ceil($verstand_max);
    my $wissen_popup = $parent_dialog->Toplevel();
	my $scrolled_area = $wissen_popup->Scrolled(
        'Frame',
        -scrollbars => 'osoe'
    )->pack(-fill => 'both', -expand => 1);
	my $wissen_dialog = $scrolled_area->Subwidget('scrolled');
    focus_dialog($wissen_popup, "Wissensfertigkeiten", $parent_dialog);
    $wissen_popup->geometry("250x100");

    my $wissen_row = 0;
	my $verstand_label;
	if($verstand_max != -1)
	{
		$verstand_label = $wissen_dialog->Label(-text => "Verstand-Punkte: $$verstand_used_ref von $verstand_max")->grid(-row => $wissen_row, -column => 4, -sticky => 'w');
	}
    my $save_button = $wissen_dialog->Button(
        -text => "Speichern",
        -command => sub {
			$$verstand_used_ref = $verstand_label->cget('-text') =~ /(\d+) von/ ? $1 : 0 if($verstand_max != -1);
            $wissen_popup->destroy;
        }
    )->grid(-row => $wissen_row, -column => 0, -columnspan => 2);
	$wissen_popup->protocol('WM_DELETE_WINDOW', sub
	{
		$$verstand_used_ref = $verstand_label->cget('-text') =~ /(\d+) von/ ? $1 : 0 if($verstand_max != -1);
		$wissen_popup->destroy;
	});

    $wissen_row++;

    my $skill_label = $wissen_dialog->Label(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'))->grid(-row => $wissen_row, -column => 4, -sticky => 'w');

    my $add_wissen_button = $wissen_dialog->Button(
        -text => "Hinzufügen",
        -command => sub {
            if (($verstand_max != -1 && $$verstand_used_ref < $verstand_max) || $skillpunkt_entry->cget('-text') > 0) {
                my $wissen_entry = $wissen_dialog->DialogBox(
                    -title   => "Wissensfertigkeit hinzufügen",
                    -buttons => ["OK", "Abbrechen"],
                );
                $wissen_entry->geometry("300x75");
                $wissen_entry->add('Label', -text => "Wissensfertigkeit:")->pack();
                my $wissen_input = $wissen_entry->add('Entry')->pack();
                my $response = $wissen_entry->Show();
                if (defined $response && $response eq "OK" && $wissen_input->get() ne "") {
                    my $new_wissen = $wissen_input->get();
                    $wissen_skills_ref->{$new_wissen} = 4;
                    if ($verstand_max != -1 && $$verstand_used_ref < $verstand_max) {
                        $$verstand_used_ref++;
						$verstand_label->configure(-text => "Verstand-Punkte: $$verstand_used_ref von $verstand_max");
                    } else {
                        $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 1);
                        $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                    }
                    $wissen_dialog->after(100, sub {
                        $$verstand_used_ref = update_wissen_list($punktetyp, $wissen_popup, $wissen_dialog, $wissen_skills_ref, $wissen_row, $verstand_used_ref, $verstand_max, $skillpunkt_entry, $skill_label, $verstand_label);
                    });
                }
            } else {
                print_wissen_keine_punkte_error($punktetyp, $wissen_dialog, $$verstand_used_ref, $verstand_max, $skillpunkt_entry);
            }
        }
    )->grid(-row => $wissen_row, -column => 0, -columnspan => 2);

    $wissen_row++;

    $wissen_dialog->after(100, sub {
        $$verstand_used_ref = update_wissen_list($punktetyp, $wissen_popup, $wissen_dialog, $wissen_skills_ref, $wissen_row, $verstand_used_ref, $verstand_max, $skillpunkt_entry, $skill_label, $verstand_label);
    });
	return $$verstand_used_ref;
}

sub print_wissen_keine_punkte_error {
    my ($punktetyp, $wissen_dialog, $verstand_used, $verstand_max, $skillpunkt_entry) = @_;
	if($verstand_max != -1)
	{
		$wissen_dialog->messageBox(
			-type    => 'Ok',
			-icon    => 'error',
			-title   => 'Keine Punkte mehr',
			-message => "Keine Punkte mehr zum Verteilen!\nPunkte verbraucht aus Verstand / 2: $verstand_used von $verstand_max\n$punktetyp übrig: " . $skillpunkt_entry->cget('-text')
		);
	}
	else
	{
		$wissen_dialog->messageBox(
			-type    => 'Ok',
			-icon    => 'error',
			-title   => 'Keine Punkte mehr',
			-message => "Keine Punkte mehr zum Verteilen!\n$punktetyp übrig: " . $skillpunkt_entry->cget('-text')
		);
	}
}

sub update_wissen_list {
    my ($punktetyp, $wissen_popup, $wissen_dialog, $wissen_skills_ref, $wissen_row, $verstand_used, $verstand_max, $skillpunkt_entry, $skill_label, $verstand_label) = @_;

    foreach my $child ($wissen_dialog->children) {
        my %gridinfo = $child->gridInfo;
        $child->gridForget() if (defined $gridinfo{-row} && $gridinfo{-row} >= $wissen_row);
    }

    my @sorted_wissen = sort keys %$wissen_skills_ref;
    my $max_length = 0;

    foreach my $wissen (@sorted_wissen) {
        my $label = $wissen_dialog->Label(-text => $wissen)->grid(-row => $wissen_row, -column => 0, -sticky => 'w');
        my $entry = $wissen_dialog->Label(-text => "W$wissen_skills_ref->{$wissen}")->grid(-row => $wissen_row, -column => 1, -sticky => 'w');

        my $increase_button = $wissen_dialog->Button(
            -text => "+",
            -command => sub {
                if (($verstand_max != -1 && $$verstand_used < $verstand_max) || $skillpunkt_entry->cget('-text') > 0) {
                    my $current_value = $wissen_skills_ref->{$wissen};
                    if ($current_value =~ /^(\d+)$/) {
                        my $number = $1;
                        if ($number == 0) {
                            $wissen_skills_ref->{$wissen} = 4;
                            if ($verstand_max != -1 && $$verstand_used < $verstand_max) {
                                $$verstand_used++;
                            } else {
                                $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 1);
								$skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                            }
                        } elsif ($number < 12) {
                            if ($number > 6) {
                                if ($verstand_max != -1 && $$verstand_used < $verstand_max - 1) {
                                    $$verstand_used += 2;
                                    $wissen_skills_ref->{$wissen} = $number + 2;
                                } elsif ($skillpunkt_entry->cget('-text') > 1) {
                                    $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 2);
									$skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                                    $wissen_skills_ref->{$wissen} = $number + 2;
                                } else {
                                    print_wissen_keine_punkte_error($punktetyp, $wissen_dialog, $$verstand_used, $verstand_max, $skillpunkt_entry);
                                }
                            } else {
                                if ($verstand_max != -1 && $$verstand_used < $verstand_max) {
									$$verstand_used++;
                                } else {
                                    $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 1);
									$skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                                }
                                $wissen_skills_ref->{$wissen} = $number + 2;
                            }
                        } elsif ($number == 12) {
                            if ($verstand_max != -1 && $$verstand_used < $verstand_max - 1) {
                                $$verstand_used += 2;
                                $wissen_skills_ref->{$wissen} = "12+1";
                            } elsif ($skillpunkt_entry->cget('-text') > 1) {
                                $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 2);
                                $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                                $wissen_skills_ref->{$wissen} = "12+1";
                            } else {
                                print_wissen_keine_punkte_error($punktetyp, $wissen_dialog, $$verstand_used, $verstand_max, $skillpunkt_entry);
                            }
                        } else {
                            if ($verstand_max != -1 && $$verstand_used < $verstand_max - 1) {
                                $$verstand_used += 2;
                                $number++;
                                $wissen_skills_ref->{$wissen} = "12+$number";
                            } elsif ($skillpunkt_entry->cget('-text') > 1) {
                                $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 2);
                                $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                                $number++;
                                $wissen_skills_ref->{$wissen} = "12+$number";
                            } else {
                                print_wissen_keine_punkte_error($punktetyp, $wissen_dialog, $$verstand_used, $verstand_max, $skillpunkt_entry);
                            }
                        }
                    } elsif ($current_value =~ /^12\+(\d+)$/) {
                        my $number = $1;
                        if ($verstand_max != -1 && $$verstand_used < $verstand_max - 1) {
                            $$verstand_used += 2;
                            $number++;
                            $wissen_skills_ref->{$wissen} = "12+$number";
                        } elsif ($skillpunkt_entry->cget('-text') > 1) {
                            $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') - 2);
                            $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                            $number++;
                            $wissen_skills_ref->{$wissen} = "12+$number";
                        } else {
                            print_wissen_keine_punkte_error($punktetyp, $wissen_dialog, $$verstand_used, $verstand_max, $skillpunkt_entry);
                        }
                    }
                    $entry->configure(-text => "W$wissen_skills_ref->{$wissen}");
                    $verstand_label->configure(-text => "Verstand-Punkte: $$verstand_used von $verstand_max") if($verstand_max != -1);
                } else {
                    print_wissen_keine_punkte_error($punktetyp, $wissen_dialog, $$verstand_used, $verstand_max, $skillpunkt_entry);
                }
            }
        )->grid(-row => $wissen_row, -column => 2, -sticky => 'w');

        my $decrease_button = $wissen_dialog->Button(
            -text => "-",
            -command => sub {
                my $current_value = $wissen_skills_ref->{$wissen};
                if ($current_value =~ /^(\d+)$/) {
                    my $number = $1;
                    if ($number == 4) {
                        $wissen_skills_ref->{$wissen} = 0;
						#delete $wissen_skills_ref->{$wissen}; #Alernativ. Manu findet es besser, wenn die Wissensfertigkeit gelöscht wird. Schwer zu implementieren.
                        if ($$verstand_used > 0) {
                            $$verstand_used--;
                        } else {
                            $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 1);
                            $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                        }
                    } elsif ($number > 0) {
                        $number -= 2;
                        $wissen_skills_ref->{$wissen} = $number;
                        if ($number >= 8) {
                            if ($verstand_max != -1 && $$verstand_used > 1) {
                                $$verstand_used -= 2;
                            } else {
                                $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 2);
                                $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                            }
                        } else {
                            if ($verstand_max != -1 && $$verstand_used > 0) {
                                $$verstand_used--;
                            } else {
                                $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 1);
                                $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                            }
                        }
                    }
                } elsif ($current_value =~ /^12\+(\d+)$/) {
                    my $number = $1;
                    if ($number > 1) {
                        $number--;
                        $wissen_skills_ref->{$wissen} = "12+$number";
                        if ($verstand_max != -1 && $$verstand_used > 1) {
                            $$verstand_used -= 2;
                        } else {
                            $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 2);
                            $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                        }
                    } else {
                        $wissen_skills_ref->{$wissen} = 12;
                        if ($verstand_max != -1 && $$verstand_used > 1) {
                            $$verstand_used -= 2;
                        } else {
                            $skillpunkt_entry->configure(-text => $skillpunkt_entry->cget('-text') + 2);
                            $skill_label->configure(-text => "$punktetyp: " . $skillpunkt_entry->cget('-text'));
                        }
                    }
                }
                $entry->configure(-text => "W$wissen_skills_ref->{$wissen}");
                $verstand_label->configure(-text => "Verstand-Punkte: $$verstand_used von $verstand_max") if($verstand_max != -1);
            }
        )->grid(-row => $wissen_row, -column => 3, -sticky => 'we');

        $max_length = length($wissen) if length($wissen) > $max_length;
        $wissen_row++;
    }

    my $new_width = 250 + $max_length * 5;
    my $new_height = 100 + $wissen_row * 25;
    $wissen_popup->geometry("${new_width}x${new_height}");

    return $$verstand_used;
}

sub update_online {
    my ($attribut, $basis_label, $mod, $gs_label, $balloon, $mod_value) = @_;

    # Berechnen Sie den neuen Wert für $online_basis
    my $new_value;
    if ($attribut =~ /^(\d+)$/) {
        $new_value = int(($mod_value + $1 ) / 2);
    } elsif ($attribut =~ /^12\+(\d+)$/) {
        $new_value = (12 + $1 + $mod_value) / 2;
    }

    # Aktualisieren Sie das Label
	my $gs_print = $new_value + $mod;
	my $gs2 = $new_value + 2 + $mod;
	my $gs4 = $new_value + 4 + $mod;
	$new_value =~ s/\./,/;
	$gs_print =~ s/\./,/;
	$gs2 =~ s/\./,/;
	$gs4 =~ s/\./,/;
    $basis_label->configure(-text => $new_value);
	$gs_label->configure(-text => "$gs_print h");
	$balloon->attach($gs_label, -balloonmsg => "$gs_print h ohne Malus, dann bis zu $gs2 h mit Malus 2, dann bis zu $gs4 h mit Malus 4, dann Pause benötigt.");
}

sub update_display {
    my ($value, $mod_value, $entry) = @_;
    if ($value =~ /^(\d+)$/) {
        my $base_value = $1;
        my $total_value = $base_value + $mod_value;
        if ($mod_value == 0) {
            $entry->configure(-text => "W$base_value");
        } elsif ($mod_value > 0) {
            $entry->configure(-text => "W$base_value+$mod_value");
        } else {
            $entry->configure(-text => "W$base_value$mod_value");
        }
    } elsif ($value =~ /^12\+(\d+)$/) {
        my $additional_value = $1;
        my $total_value = $additional_value + $mod_value;
        if ($total_value == 0) {
            $entry->configure(-text => "W12");
        } elsif ($total_value < 0) {
            $entry->configure(-text => "W12$total_value");
        } else {
            $entry->configure(-text => "W12+$total_value");
        }
    }
}

sub update_display_avatar {
    my ($value, $mod_value, $entry, $skill, $char_attributes, $char_attr_mods, $char_skills, $char_skill_mods) = @_;
    
	my $chskill = $skill;
	my $attr = "";
	if($skill =~ /Nahkampf|Fernkampf/)
	{
		$chskill = "Kämpfen";
		$attr = "Reaktion";
	}
	elsif($skill =~ /Heimlichkeit|Diebstahl|Athletik/)
	{
		$attr = "Reaktion";
	}
	elsif($skill eq "Fahrzeug lenken")
	{
		$chskill = "Fahren";
		$attr = "Reaktion";
	}
	elsif($skill =~ /Inspirieren|Provozieren|Überreden/)
	{
		$attr = "Charisma";
	}
	if(defined $char_skills->{$chskill})
	{
        # Gesamtbonus berechnen
		
		my $chskill_value = get_bonus_skill($char_skills->{$chskill}, $char_skill_mods->{$chskill}, 6);
		if($chskill_value =~ /^(\d+).(\d+)$/)
		{
			$chskill_value  = $1;
			my $chskill_mod = $2;
			
			my $chatttr = 0;
			$chatttr = get_bonus_attr($char_attributes->{$attr}, $char_attr_mods->{$attr}, 8) if($attr ne "");

			if($value =~ /^12\+(\d+)$/)
			{
				my $total_value = ceil($1 + $mod_value + $chatttr + ($chskill_value / 2)) + $chskill_mod;
				if ($total_value == 0)
				{
					$entry->configure(-text => "W12");
				}
				elsif ($total_value < 0)
				{
					$entry->configure(-text => "W12$total_value");
				}
				else
				{
					$entry->configure(-text => "W12+$total_value");
				}
			}
			else
			{
				$chskill_value += $value;
				if($chskill_value > 12)
				{
					$mod_value += ($chskill_value - 12) / 2;
					$chskill_value = 12;
				}
				my $total_value = ceil($chatttr + $mod_value);
				if ($total_value == 0)
				{
					$entry->configure(-text => "W$chskill_value");
				}
				elsif ($total_value > 0)
				{
					$entry->configure(-text => "W$chskill_value+$total_value");
				}
				else
				{
					$entry->configure(-text => "W$chskill_value$total_value");
				}
			}
		}
    }
	elsif($attr ne "")
	{
		my $chatttr = get_bonus_attr($char_attributes->{$attr}, $char_attr_mods->{$attr}, 8);

		if($value =~ /^12\+(\d+)$/)
		{
			my $total_value = ceil($1 + $mod_value + $chatttr);
			if ($total_value == 0)
			{
				$entry->configure(-text => "W12");
			}
			elsif ($total_value < 0)
			{
				$entry->configure(-text => "W12$total_value");
			}
			else
			{
				$entry->configure(-text => "W12+$total_value");
			}
		}
		else
		{
			my $total_value = ceil($chatttr + $mod_value);
			if ($total_value == 0)
			{
				$entry->configure(-text => "W$value");
			}
			elsif ($total_value > 0)
			{
				$entry->configure(-text => "W$value+$total_value");
			}
			else
			{
				$entry->configure(-text => "W$value$total_value");
			}
		}
	}
	else
	{
        if ($value =~ /^(\d+)$/) {
			my $base_value = $1;
			if ($mod_value == 0) {
				$entry->configure(-text => "W$base_value");
			} elsif ($mod_value > 0) {
				$entry->configure(-text => "W$base_value+$mod_value");
			} else {
				$entry->configure(-text => "W$base_value$mod_value");
			}
		} elsif ($value =~ /^12\+(\d+)$/) {
			my $additional_value = $1;
			my $total_value = $additional_value + $mod_value;
			if ($total_value == 0) {
				$entry->configure(-text => "W12");
			} elsif ($total_value < 0) {
				$entry->configure(-text => "W12$total_value");
			} else {
				$entry->configure(-text => "W12+$total_value");
			}
		}
    }
}

sub update_parade {
    my (
        $skills_ref,      # Referenz auf die Fertigkeiten-Hash
        $skill_mods_ref,  # Referenz auf die Fertigkeiten-Modifikatoren
        $attributes_ref,  # Referenz auf die Attribute
        $attr_mods_ref,   # Referenz auf die Attributs-Modifikatoren
        $parade_basis,    # Tk-Label für Basiswert
        $parademod_entry, # Tk-Entry für Modifikator
        $paradegs_entry   # Tk-Label für Gesamtwert
    ) = @_;

    # Werte aus den Hashes holen (mit Standardwert 0 falls nicht vorhanden)
    my $kampf = $skills_ref->{'Kämpfen'} || 0;
	$kampf = $1 + $2 if($kampf =~ /^(\d+)\+(\d+)/);
	$kampf+= ($skill_mods_ref->{'Kämpfen'} || 0);

    my $reaktion = $attributes_ref->{'Reaktion'} || 0;
	$reaktion = $1 + $2 if($reaktion =~ /^(\d+)\+(\d+)/);
	$reaktion+= ($attr_mods_ref->{'Reaktion'} || 0);
	
    my $ausw = $skills_ref->{'Ausweichen'} || 0;
	$ausw = $1 + $2 if($ausw =~ /^(\d+)\+(\d+)/);
	$ausw+= ($skill_mods_ref->{'Ausweichen'} || 0);

    # Basiswert berechnen und aufrunden
    my $basis = ceil(2 + ($kampf/2) + ($reaktion/4) + ($ausw/2));

    # Modifikator aus dem Entry-Feld holen
    my $mod = $parademod_entry->get() || 0;
    $mod = 0 unless $mod =~ /^[+-]?\d+$/; # Sicherstellen, dass es eine Zahl ist

    # UI-Elemente aktualisieren
    $parade_basis->configure(-text => $basis);
    $paradegs_entry->configure(-text => $basis + $mod);
}

sub update_parade_avatar {
    my (
        $char_skills_ref,      # Referenz auf die Fertigkeiten-Hash
        $char_skill_mods_ref,  # Referenz auf die Fertigkeiten-Modifikatoren
        $char_attributes_ref,  # Referenz auf die Attribute
        $char_attr_mods_ref,   # Referenz auf die Attributs-Modifikatoren
        $parade_basis,    # Tk-Label für Basiswert
        $parademod_entry, # Tk-Entry für Modifikator
        $paradegs_entry,   # Tk-Label für Gesamtwert
		$nahkampf,
		$nk_mod
    ) = @_;
	
	my $ausweichen;
	my $reaktion;
	$nahkampf = 12 + $1 if($nahkampf =~ /^12\+(\d+)$/);
	if($char_skills_ref->{'Ausweichen'} =~ /^12\+(\d+)$/)
	{
		$ausweichen = 12 + $1;
	}
	else
	{
		$ausweichen = $char_skills_ref->{'Ausweichen'};
	}
	
	my $basis = ceil(2 + (($nahkampf + $nk_mod) / 2) + (($ausweichen + $char_skill_mods_ref->{'Ausweichen'}) / 2) + get_bonus_attr($char_attributes_ref->{'Reaktion'}, $char_attr_mods_ref->{'Reaktion'}, 8));
	my $mod = $parademod_entry->get() || 0;
	$parade_basis->configure(-text => $basis);
    $paradegs_entry->configure(-text => $basis + $mod);
}

sub update_robust {
    my (
        $attributes_ref,  # Referenz auf die Attribute
        $attr_mods_ref,   # Referenz auf die Attributs-Modifikatoren
        $robust_basis,    # Tk-Label für Basiswert
        $robustmod_entry, # Tk-Entry für Modifikator
        $robustgs_entry   # Tk-Label für Gesamtwert
    ) = @_;

	my $kv = $attributes_ref->{'Körperliche Verfassung'} || 0;
	$kv = $1 + $2 if($kv =~ /^(\d+)\+(\d+)/);
    # Basiswert berechnen und aufrunden
    my $basis = ceil(2 + ($kv / 2) + ($attr_mods_ref->{'Körperliche Verfassung'} || 0));

    # Modifikator aus dem Entry-Feld holen
    my $mod = $robustmod_entry->get() || 0;
    $mod = 0 unless $mod =~ /^[+-]?\d+$/; # Sicherstellen, dass es eine Zahl ist

    # UI-Elemente aktualisieren
    $robust_basis->configure(-text => $basis);
    $robustgs_entry->configure(-text => $basis + $mod);
}

sub update_robust_avatar {
    my (
        $konst,
        $konst_mod,
        $robust_basis,    # Tk-Label für Basiswert
        $robustmod_entry, # Tk-Entry für Modifikator
        $robustgs_entry   # Tk-Label für Gesamtwert
    ) = @_;

	$konst = $1 + $2 if($konst =~ /^(\d+)\+(\d+)/);
    # Basiswert berechnen und aufrunden
    my $basis = ceil(2 + ($konst / 2) + ($konst_mod || 0));

    # Modifikator aus dem Entry-Feld holen
    my $mod = $robustmod_entry->get() || 0;
    $mod = 0 unless $mod =~ /^[+-]?\d+$/; # Sicherstellen, dass es eine Zahl ist

    # UI-Elemente aktualisieren
    $robust_basis->configure(-text => $basis);
    $robustgs_entry->configure(-text => $basis + $mod);
}

sub get_bonus_attr
{
    my ($value, $mod, $throttle) = @_;
    $value = $1 + $2 if($value =~ /(\d+)\+(\d+)/);
    if($value < $throttle)
	{
		return $mod;
	}
	else
	{
		return (($value - $throttle) / 2) + $mod;
	}
}

sub get_bonus_attr_no_mod
{
    my ($value, $throttle) = @_;
    $value = $1 + $2 if($value =~ /(\d+)\+(\d+)/);
    if($value < $throttle)
	{
		return 0;
	}
	else
	{
		return (($value - $throttle) / 2);
	}
}

sub get_bonus_skill
{
    my ($value, $mod, $throttle) = @_;
	my $bonus = 0;
	if($value =~ /^(\d+)\+(\d+)$/)
	{
		$value = $1;
		$bonus = $2;
	}
    if($value < $throttle)
	{
		if($mod < 0)
		{
			return "0-$mod";
		}
		else
		{
			return "0+$mod";
		}
	}
	else
	{
		if($mod + $bonus < 0)
		{
			return ($value - $throttle) . "-" . ($mod + $bonus);
		}
		else
		{
			return ($value - $throttle) . "+" . ($mod + $bonus);
		}
	}
}

sub print_rank_message
{
    my ($dialog, $rank_entry, $rank, $gain) = @_;
	$rank_entry->configure(-text => $rank);
	if($gain ne "")
	{
		$dialog->messageBox(
			-type    => 'Ok',
			-icon    => 'info',
			-title   => 'Neuer Rang',
			-message => "Herzlichen Glückwunsch! Du hast jetzt den Rang $rank!\nUnd $gain!"
		);
	}
	else
	{
		$dialog->messageBox(
			-type    => 'Ok',
			-icon    => 'info',
			-title   => 'Neuer Rang',
			-message => "Herzlichen Glückwunsch! Du hast jetzt den Rang $rank!"
		);
	}
}

sub show_combined_distribution_popup {
    my (%args) = @_;
    my $parent       = $args{parent};
    my $title        = $args{title} // "Punkte verteilen";
    my $message      = $args{message} // "Bitte verteile die erhaltenen Bonuspunkte:";
    my $bonuses_data = $args{bonuses_data};
	
	my %distributable_bonuses = (
		'Verteidigung' => ['Parade', 'Robustheit'],
		'Angriffsart'  => ['Nahkampf', 'Fernkampf', 'Machtnutzung'],
		'Trank'        => ['Heiltrank', 'Machttrank']
	);

    # --- Interne Datenstrukturen ---
    my %widgets;
    my %point_values;
    my %remaining_vars;
    my %section_valid;

    my $combined_result = undef;

    # --- Pop-up Fenster erstellen ---
    my $dist_popup = $parent->Toplevel();
	focus_dialog($dist_popup, $title, $parent);
	
	my $start_width = 450;  # Breite, die wahrscheinlich meistens passt
    my $calc_height = 150;

    # Positioniere mittig über Parent
    
    
	my $scrolled_area = $dist_popup->Scrolled(
		'Frame',
		-scrollbars => 'osoe' # Scrollbars nur rechts/unten bei Bedarf
	)->pack(-fill => 'both', -expand => 1); # Füllt das gesamte Dialogfenster

	# --- Der eigentliche Inhalts-Frame ---
	my $popup = $scrolled_area->Subwidget('scrolled');
    $dist_popup->protocol('WM_DELETE_WINDOW', sub {
		my $all_sections_ok = 1;
		foreach my $b_type (keys %{ $bonuses_data // {} }) {
			next unless exists $section_valid{$b_type}; # Nur relevante Sektionen prüfen
			unless ($section_valid{$b_type}) {
				$all_sections_ok = 0;
				last;
			}
		}

        if (!$all_sections_ok && keys %section_valid > 0)
		{ # Nur fragen, wenn es verteilbare Boni gab, die nicht OK sind
            my $response = $popup->messageBox(
                -title   => "Abbrechen?",
                -message => "Die Punkte sind nicht korrekt verteilt und gehen verloren.\nWollen Sie wirklich abbrechen?",
                -type    => 'YesNo',
                -icon    => 'question',
                -default => 'No'
            );
            if ((defined $response && $response eq 'Yes') || $all_sections_ok || keys %section_valid == 0)
			{
				 if (defined $args{on_close_callback} && ref $args{on_close_callback} eq 'CODE')
				 {
					 $args{on_close_callback}->('cancel', undef); # Status 'cancel', kein Ergebnis
				 }
				 else
				 {
					 $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'Fehler', -message => "Kein on_close_callback definiert!" );
				 }
				 $dist_popup->destroy;
				# Wenn 'No', bleibt das Fenster offen
			}
			else { # Entweder alles OK oder keine relevanten Sektionen
             if (defined $args{on_close_callback} && ref $args{on_close_callback} eq 'CODE') { $args{on_close_callback}->('cancel', undef); } # Auch hier Cancel melden
             else { $mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'Fehler', -message => "Kein on_close_callback definiert!" ); }
             $dist_popup->destroy;
			}
		}
    });

    $popup->Label(-text => $message, -justify => 'left')->pack(-pady => 10, -padx => 10, -anchor => 'w');

	my $has_distributable_items = 0;
	if(defined $bonuses_data->{Verteidigung} || defined $bonuses_data->{Angriffsart} || defined $bonuses_data->{Trank})
	{
		$popup->Label(-text => "\nZusätzlich müssen noch folgende Punkte verteilt werden:\n", -justify => 'left')->pack(-pady => 10, -padx => 10, -anchor => 'w');
		my $main_frame = $popup->Frame()->pack(-fill => 'both', -expand => 1, -padx => 5, -pady => 5);

		# --- Dynamisch Abschnitte für jeden Bonus-Typ erstellen ---
		foreach my $bonus_type (sort keys %$bonuses_data)
		{
			if (defined $distributable_bonuses{$bonus_type})
			{
				$has_distributable_items = 1;
				my $total_points = $bonuses_data->{$bonus_type};
				my @options = @{ $distributable_bonuses{$bonus_type} // [] };

                next unless $total_points > 0 && @options;
				if($bonus_type eq 'Verteidigung' || $bonus_type eq 'Trank')
				{
					$calc_height += 160;
				}
				else
				{
					$calc_height += 210;
				}

				$section_valid{$bonus_type} = ($total_points == 0);

				# Rahmen für diesen Abschnitt
				my $section_frame = $main_frame->Frame(
					-borderwidth => 2, -relief => 'groove'
				)->pack(-fill => 'x', -pady => 5, -padx => 5);
				$widgets{$bonus_type}{_frame} = $section_frame;

				$section_frame->Label(
					-text => "$bonus_type (insgesamt $total_points Punkte):",
					-font => '{weight bold}' # Fettdruck
				)->pack(-anchor => 'w', -pady => (5), -padx => 5);

				# Einträge für jede Option in diesem Abschnitt
				foreach my $option (@options)
				{
					my $entry_frame = $section_frame->Frame()->pack(-fill => 'x', -pady => 1, -padx => 10);
					$widgets{$bonus_type}{$option}{_entry_frame} = $entry_frame;

					$entry_frame->Label(-text => "$option:", -width => 15, -anchor => 'w')->pack(-side => 'left');

					$point_values{$bonus_type}{$option} = 0; # Startwert für Variable

					my $entry = $entry_frame->Entry(
						-width => 5,
						-textvariable => \$point_values{$bonus_type}{$option},
						-validate => 'key',
						-validatecommand => [\&validate_digit, '%P']
					);
					$entry->pack(-side => 'left');
					$widgets{$bonus_type}{$option}{entry} = $entry;

					# Binden, um den Status *dieses Abschnitts* und den globalen OK-Button zu prüfen
					$entry->bind('<KeyRelease>', sub {
						 # OK-Button Referenz wird später geholt
						 update_section_status(
							 $bonus_type, # Welcher Abschnitt wird geändert?
							 $bonuses_data, # Gesamtübersicht (für total_points)
							 \%point_values, # Aktuelle Werte aller Entries
							 \%remaining_vars, # Variablen für Restpunkte-Labels
							 \%section_valid, # Status aller Sektionen
							 $popup->{_ok_button} # Der globale OK-Button
						 );
					 });
					$entry->insert(0, "0"); # Initial 0 eintragen
				}
				# Label für verbleibende Punkte in diesem Abschnitt
				$remaining_vars{$bonus_type} = "Verbleibend: $total_points"; # Initialwert für Variable
				my $remaining_label = $section_frame->Label(
					-textvariable => \$remaining_vars{$bonus_type},
					-anchor => 'w'
				)->pack(-anchor => 'e', -pady => 5, -padx => 10);
				$widgets{$bonus_type}{_remaining_label} = $remaining_label;
			}

		} # Ende foreach $bonus_type
		
		

		# --- Globale Buttons ---
		my $button_frame = $popup->Frame()->pack(-pady => 10);

		my $ok_button = $button_frame->Button(
			-text    => "Bestätigen",
			-state   => $has_distributable_items ? 'disabled' : 'normal',
			-command => sub
			{
				my %result_copy;
                     foreach my $b_type (keys %point_values) {
                         $result_copy{$b_type} = { %{$point_values{$b_type}} };
                     }
				if (defined $args{on_close_callback} && ref $args{on_close_callback} eq 'CODE') {
				$args{on_close_callback}->('ok', \%result_copy); # Status 'ok' und Ergebnis übergeben
			} else {
				$mw->messageBox( -type => 'Ok', -icon => 'error', -title => 'Fehler', -message => "Kein on_close_callback definiert!" );
			}
			$dist_popup->destroy;
			}
		)->pack(-side => 'left', -padx => 5);
		$popup->{_ok_button} = $ok_button; # Referenz speichern
		if ($has_distributable_items)
		{
			foreach my $b_type (keys %widgets)
			{
				 # Sicherstellen, dass _ok_button existiert, bevor es verwendet wird
				 if (exists $popup->{_ok_button})
				 {
					update_section_status(
						 $b_type, $bonuses_data, \%point_values, \%remaining_vars, \%section_valid, $popup->{_ok_button}
					);
				 }
			}
		}
		
	}
	
	$scrolled_area->bind('<MouseWheel>', [\&scroll_widget_y, $scrolled_area, '%D']);
    $scrolled_area->bind('<Button-4>',   [\&scroll_widget_y, $scrolled_area, -1]);
    $scrolled_area->bind('<Button-5>',   [\&scroll_widget_y, $scrolled_area,  1]);
    $popup->bind('<MouseWheel>', [\&scroll_widget_y, $scrolled_area, '%D']);
    $popup->bind('<Button-4>',   [\&scroll_widget_y, $scrolled_area, -1]);
    $popup->bind('<Button-5>',   [\&scroll_widget_y, $scrolled_area,  1]);

	$popup->update;
	$dist_popup->update;
	my $final_width = $start_width;
    my $final_height = $calc_height;

    # Max Größe begrenzen
    my $max_w = $parent->screenwidth * 0.9; # Etwas mehr Platz erlauben
    my $max_h = $parent->screenheight * 0.9;
    $final_width = $max_w if $final_width > $max_w;
    $final_height = $max_h if $final_height > $max_h;
    # Mindestgröße sicherstellen
    $final_width = 300 if $final_width < 300;
    $final_height = 200 if $final_height < 200;
	my $parent_x = $parent->rootx;
    my $parent_y = $parent->rooty;
    my $parent_w = $parent->width;
    my $parent_h = $parent->height;
    my $popup_x = $parent_x + int(($parent_w - $final_width) / 2);
    my $popup_y = $parent_y + int(($parent_h - $final_height) / 2);
    $popup_x = 0 if $popup_x < 0;
    $popup_y = 0 if $popup_y < 0;

    # Setze FINALE Größe UND Position
    $dist_popup->geometry("${final_width}x${final_height}+${popup_x}+${popup_y}");
	$dist_popup->update;
	$popup->update;

	return;
}


# --- Hilfsfunktion zum Aktualisieren des Status eines Abschnitts und des OK-Buttons ---
sub update_section_status {
    my ($changed_bonus_type, $all_bonuses_data, $points_values_ref,
        $remaining_vars_ref, $section_valid_ref, $global_ok_button) = @_;

    # 1. Status der GEÄNDERTEN Sektion aktualisieren
    my $total_for_section = $all_bonuses_data->{$changed_bonus_type};
    my $current_sum_section = 0;
    foreach my $option (keys %{ $points_values_ref->{$changed_bonus_type} // {} }) {
        my $val = $points_values_ref->{$changed_bonus_type}{$option} // 0;
        $val = 0 unless $val =~ /^\d+$/;
        $current_sum_section += $val;
    }
    my $remaining_section = $total_for_section - $current_sum_section;

    # Restpunkte-Label aktualisieren
    $remaining_vars_ref->{$changed_bonus_type} = "Verbleibend: $remaining_section";

    # Gültigkeitsstatus für diese Sektion setzen
    if ($current_sum_section == $total_for_section) {
        $section_valid_ref->{$changed_bonus_type} = 1;
        $remaining_vars_ref->{$changed_bonus_type} .= " (Ok)";
    } else {
        $section_valid_ref->{$changed_bonus_type} = 0;
        $remaining_vars_ref->{$changed_bonus_type} .= ($current_sum_section > $total_for_section) ? " (Zu viel!)" : " (Zu wenig!)";
    }

    # 2. Globalen OK-Button-Status prüfen: Sind ALLE Sektionen gültig?
    my $all_sections_ok = 1;
    foreach my $b_type (keys %$section_valid_ref) {
        unless ($section_valid_ref->{$b_type}) {
            $all_sections_ok = 0;
            last; # Eine ungültige Sektion reicht
        }
    }

    # OK-Button aktivieren/deaktivieren
    if ($all_sections_ok) {
        $global_ok_button->configure(-state => 'normal');
    } else {
        $global_ok_button->configure(-state => 'disabled');
    }
}

sub validate_digit {
     my ($P) = @_; # Proposed value
    # Erlaube leeren String, optionales Vorzeichen, Ziffern
    return 1 if ($P =~ /^(\d*)?$/);
    return 0;
}

sub open_notizen_window {
	my ($hash_ref, $parent) = @_;
    my $notizen_window = $parent->Toplevel;
	focus_dialog($notizen_window, 'Notizen', $parent);

    my $text_field = $notizen_window->Scrolled('Text', -scrollbars => 'se', -width => 80, -height => 20)->pack(-pady => 10);
	if (defined $hash_ref->{notizen}) {
			$text_field->insert('end', $hash_ref->{notizen});
		}
    my $save_button = $notizen_window->Button(-text => "Speichern", -command => sub {
        my $content = $text_field->get('1.0', 'end-1c');
        $hash_ref->{notizen} = $content;
        $notizen_window->destroy;
    })->pack(-pady => 10);
}