use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'DBIx::Class::OptimisticLocking',
    AUTHOR              => 'Brian Phillips <bphillips@cpan.org>',
    VERSION_FROM        => 'lib/DBIx/Class/OptimisticLocking.pm',
    ABSTRACT_FROM       => 'lib/DBIx/Class/OptimisticLocking.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
		'DBIx::Class' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'DBIx-Class-OptimisticLocking-*' },
);
