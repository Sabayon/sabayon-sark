#!/usr/bin/perl
# purge old versions script - mudler@sabayon.org
# input: as env (PACKAGES) a list of packages with version
# output: the packages which should remain or should be removed (set the OUTPUT_REMOVED and KEEP env variable accordingly)
# PACKAGES: the list of packages to inspect
# KEEP: if set to a number, there will be kept the latest $n versions of each package. set to -1 to disable
# OUTPUT_REMOVED: if set to 1 it returns the package of the set that should be removed. if set to 0 it returns the packages that satisfy the clause (order to keep the greater versions in the repositories)

sub natural_order {
    my @a = @_;
    return [
        @a[    #natural sort order for strings containing numbers
          map { unpack "N", substr( $_, -4 ) } #going back to normal representation
          sort
          map {
              my $key = $a[$_];
              $key =~ s[(\d+)][ pack "N", $1 ]ge
                ;    #transforming all numbers in ascii representation
              $key . pack "CNN", 0, 0, $_
          } 0 .. $#a
        ]
    ];
}

sub to_atom { my $p = shift; $p =~ s/-[0-9]{1,}.*$//; return $p; }

my $keep           = $ENV{KEEP_PREVIOUS_VERSIONS} // 3;
my $output_removed = $ENV{OUTPUT_REMOVED}         // 1;
my $packages = $ENV{PACKAGES};

sub purge {
    my @packages_to_purge = @_;

    return @packages_to_purge if $keep == -1;

    my $atom_cache;
    my @return;

    push( @{ $atom_cache->{ +to_atom($_) } }, $_ )
      for @packages_to_purge;    # fill in hash
    $atom_cache->{$_} = natural_order( @{ $atom_cache->{$_} } )
      for ( keys %{$atom_cache} );    # order arrays in hash

    if ( $output_removed == 0 ) {
        do {
            my $l = @{ $atom_cache->{$_} };
            if ( $l > $keep ) {
                splice( @{ $atom_cache->{$_} }, 0, $l - $keep );
            }
          }
          for ( keys %{$atom_cache} );
    }
    elsif ( $output_removed == 1 ) {
        for ( keys %{$atom_cache} ) {
            if ( @{ $atom_cache->{$_} } >= $keep ) {
                splice( @{ $atom_cache->{$_} }, -$keep );
            }
            else { $atom_cache->{$_} = []; }
        }
    }

    push( @return, @{ $atom_cache->{$_} } ) for ( keys %{$atom_cache} );

    return @return;

}

print join( " ", purge(split(/ /,$packages)) );
