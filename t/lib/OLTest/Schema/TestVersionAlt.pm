package OLTest::Schema::TestVersionAlt;

use strict;
use warnings;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/ OptimisticLocking PK::Auto Core /);
__PACKAGE__->table('test_version_alt');
__PACKAGE__->add_columns( qw/ id col1 myversion / );

__PACKAGE__->optimistic_locking_mode('version');
__PACKAGE__->optimistic_locking_version_column('myversion');

1;
