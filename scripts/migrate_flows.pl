use strict;
use warnings;

use XML::LibXML;
use File::Path;
use File::Copy;
use Try::Tiny;

my $src_path = shift;
$src_path =~ s/\/$//; # if the param ended with a slash, get rid of that s!@t

my $flow_dir = $src_path . '/flows';
my $definition_dir = $src_path . '/flowDefinitions';
my $new_dir = $src_path . '/newFlows';
rmtree $new_dir; #just in case
mkdir $new_dir or die "Failed to create a working directory\n $!";

my %flows_active;
my @flows_draft;

my $parser = XML::LibXML->new();

# get all flow definition files
print "Sorting flows into active and drafts...\n";
opendir DIR, $definition_dir or die "Failed to open directory $definition_dir\n $!";
foreach my $file (readdir DIR) {
	next if $file =~ /^\.|^\.\./;
	my $filepath = $definition_dir.'/'.$file;
	my $flow = removeExtension($file);
	#print "Parsing $file";
	my $version = 0;
	my $xmldoc = $parser->parse_file($filepath);
	foreach my $node ($xmldoc->getElementsByLocalName('activeVersionNumber')) {
		$version = $node->textContent;
	}
	if (0 < $version) {
		$flows_active{$flow} = $version;
	}
	else {
		push @flows_draft, $flow;
	}
}
closedir DIR or die $!;

# update flow files for active flows
print "Parsing active flows...\n";
foreach my $flow (keys %flows_active) {
	my $value = $flows_active{$flow};
	if (0 != $value) {
		my $filepath = $flow_dir.'/'.$flow.'-'.$value.'.flow';
		print "> Updating:\t$flow-$value.flow\n";
		try {
			createNew($parser->parse_file($filepath), $flow, 'Active');
		}
		catch {
			print "> NOT_FOUND:\t$flow\n";
		};
	}
}

# iterate through the flows directory to find the latest versions of inactive flows
print "Parsing inactive flows...\n";
opendir DIR, $flow_dir or die "Failed to open directory $flow_dir\n $!";
my @files = readdir DIR;
closedir DIR or die $!;

my $bp = 0; #breakpoint
foreach my $flow (@flows_draft) {
	my ($filepath, $filename);
	for (my $i=$bp; $i<scalar(@files); $i++) {
		my $file = $files[$i];
		next if $file =~ /^\.|^\.\./;
		if (index($file, $flow) != -1) {
			$filepath = $flow_dir.'/'.$file;
			$filename = $file;
		}
		elsif (defined $filename) {
			# means it's first file after match
			$bp = $i;
			last;
		}
	}
	# readdir is alphabetical, so last found is the last version
	if (defined $filename) {
		print "> Updating:\t$filename\n";
		createNew($parser->parse_file($filepath), $flow, 'Draft');
	}
	else {
		print "> NOT_FOUND:\t$flow\n";
	}
}


# cleanup
rmtree $definition_dir or die $!;
rmtree $flow_dir or die $!;
move $new_dir, $flow_dir or die $!;
#rmdir $new_dir or die $!;

# helper for creating new version
sub createNew {
	my ($xmldoc, $name, $status) = (shift, shift, shift);
	foreach my $master_node ($xmldoc->getElementsByLocalName('Flow')) {
		my $node = $xmldoc->createElement('status');
		$node->appendText($status);
		$master_node->appendChild($xmldoc->createTextNode("\t"));
		$master_node->appendChild($node);
		$master_node->appendChild($xmldoc->createTextNode("\n"));
	}
	$xmldoc->toFile($new_dir.'/'.$name.'.flow');
}

# helper for matching component names rather then file names
sub removeExtension {
	my $filename = shift;
	$filename =~ s/\..*$//;
	return $filename;
}