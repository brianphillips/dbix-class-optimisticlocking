#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'DBIx::Class::OptimisticLocking' );
}

diag( "Testing DBIx::Class::OptimisticLocking $DBIx::Class::OptimisticLocking::VERSION, Perl $], $^X" );
