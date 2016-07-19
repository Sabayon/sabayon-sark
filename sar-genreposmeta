#!/usr/bin/perl
use JSON;
use LWP::UserAgent;

my %packages;
my $arches   = $ENV{ARCHES} // "amd64";
my $base_url = $ENV{VAGRANT_DIR} // "/vagrant/artifacts/";

my @ARCHES = split(/ /,$arches);
sub getarray {
    my $url = shift;
    my @res;
    open FILE, "<$url";
    @res = <FILE>;
    chomp(@res);
    return @res;
}

sub get_packages {
    my $repo = shift;
    my @packages;
    foreach my $arch (@ARCHES) {

        push( @packages,
            map { $_ .= " $repo $arch"; }
              getarray( $base_url . $repo . "/PKGLIST-" . $arch ) );

    }
    return @packages;
}

my @packages;
foreach my $key ( getarray( $base_url . 'AVAILABLE_REPOSITORIES' ) ) {
    push( @packages, get_packages($key) );
}

my $packs;
foreach my $p (@packages) {
    my @parts = split( / /, $p );
    $parts[0] =~ s/\~.*//g;
    $p = {
        "package"    => $parts[0],
        "repository" => $parts[1],
        "arch"       => $parts[2]
    };
}
print "Generating JSONP metadata\n";
open FILE, ">$base_url/metadata.json";
print FILE "parsePackages(" . encode_json( \@packages ) . ")";
close FILE;
