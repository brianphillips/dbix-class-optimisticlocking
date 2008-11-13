package    # hide from PAUSE
  OLTest::Schema;

use base qw/DBIx::Class::Schema/;

__PACKAGE__->load_classes(qw/TestDirty TestDirtyInsignificant TestAll TestVersion TestVersionAlt/);

1;
