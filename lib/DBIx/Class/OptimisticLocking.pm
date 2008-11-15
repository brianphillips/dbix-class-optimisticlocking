package DBIx::Class::OptimisticLocking;

use warnings;
use strict;

use base 'DBIx::Class';
use Carp qw(croak);

=head1 NAME

DBIx::Class::OptimisticLocking - Optimistic locking support for
DBIx::Class

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

This module allows the user to utilize optimistic locking when updating
a row.

Example usage:

	package DB::Main::Orders;

	use base qw/DBIx::Class/;

	__PACKAGE__->load_components(qw/OptimisticLocking Core/);

	__PACKAGE__->optimistic_locking_strategy('dirty'); # this is the default behavior

=head1 PURPOSE

Optimistic locking is an alternative to using exclusive locks when
you have the possibility of concurrent, conflicting updates in your
database.  The basic principle is you allow any and all clients to issue
updates and rather than preemptively synchronizing all data modifications
(which is what happens with exclusive locks) you are "optimistic" that
updates won't interfere with one another and the updates will only fail
when they do in fact interfere with one another.

Consider the following scenario (in timeline order, not in the same
block of code):

	my $order = $schema->resultset('Orders')->find(1);

	# some other different, concurrent process loads the same object
	my $other_order = $schema->resultset('Orders')->find(1);

	$order->status('fraud review');
	$other_order->status('processed');

	$order->update; # this succeeds
	$other_order->update; # this fails when using optimistic locking

Without optimistic locking (or exclusive locking), the example order
would have two sequential updates issued with the second essentially
erasing the results of the first.  With optimistic locking, the second
update (on C<$other_order>) would fail.

This optimistic locking is typically done by adding additional
restrictions to the C<WHERE> clause of the C<UPDATE> statement.  These
additional restrictions ensure the data is still in the expected state
before applying the update.  This DBIx::Class::OptimisticLocking component
provides a few different strategies for providing this functionality.

=head1 CONFIGURATION

=head2 optimistic_locking_strategy

This configuration controls the main functionality of this component.
The current recognized optimistic locking modes supported are:

=over 4

=item * dirty

When issuing an update, the C<WHERE> clause of the update will include
all of the original values of the columns that are being updated.
Any columns that are not being updated will be ignored.

=item * version

When issuing an update, the C<WHERE> clause of the update will include
a check of the C<version> column (or otherwise configured column using
L<optimistic_locking_version_column>).  The C<version> column will
also be incremented on each update as well.  The exception is if all
of the updated columns are in the L<optimistic_locking_ignore_columns>
configuration.

=item * all

When issuing an update, the C<WHERE> clause of the update will include
a check on each column in the object regardless of whether they were
updated or not.

=item * none (or any other value)

This turns off the functionality of this component.  But why would you
load it if you don't need it? :-)

=back

=head2 optimistic_locking_ignore_columns

Occassionally you may elect to ignore certain columns that are not
significant enough to detect colisions and cause the update to fail.
For instance, if you have a timestamp column, you may want to add that
to this list so that it is ignored when generating the C<UPDATE> where
clause for the update.

=head2 optimistic_locking_version_column

If you are using 'version' as your L<optimistic_locking_strategy>,
you can optionally specify a different name for the column used for
version tracking.  If an alternate name is not passed, the component
will look for a column named C<version> in your model.

=cut

__PACKAGE__->mk_classdata(optimistic_locking_strategy => 'dirty');
__PACKAGE__->mk_classdata('optimistic_locking_ignore_columns');
__PACKAGE__->mk_classdata(optimistic_locking_version_column => 'version');

my %valid_strategies = map { $_ => undef } qw(dirty all none version);

sub optimistic_locking_strategy {
	my @args = @_;
	my $class = shift(@args);
	my ($strategy) = $args[0];
	croak "invalid optimistic_locking_strategy $strategy" unless exists $valid_strategies{$strategy};
	return $class->_opt_locking_strategy_accessor(@args);
}

sub _get_original_columns {
	my $self = shift;
	my %columns = ( $self->get_columns, %{ $self->{_opt_locking_orig_values} || {} } );
	return %columns;
}


sub _get_original_column {
	my $self = shift;
	my $column = shift;
	my %columns = $self->_get_original_columns;
	return exists $columns{$column} ? $columns{$column} : ();
}

=head1 EXTENDED METHODS

=head2 set_column

See L<DBIx::Class::Row::set_column> for basic usage.

In addition to the basic functionality, this method will track the
original value of the column if the optimistic locking mode is set
to C<dirty> or C<all> and this is the first time this column has been
updated.  So it can be used as a C<WHERE> condition when the C<UPDATE>
is issued.

=cut

sub set_column {
	my @args = @_;
	my $self = shift(@args);
	my ($column) = $args[0];

	# save off the original if this is the first time the column has been changed
	if($self->optimistic_locking_strategy ne 'none' && !$self->is_column_changed($column)){

            $self->{_opt_locking_orig_values}->{$column} = $self->get_column($column);
	}
	return $self->next::method(@args);
}

=head2 update

See L<DBIx::Class::Row::update> for basic usage.

Before issuing the actual update, this component injects additional
criteria that will be used in the C<WHERE> clause in the C<UPDATE>. The
criteria that is used depends on the L<CONFIGURATION> defined in the
model class.

=cut

sub update {
	my $self = shift;
	my $upd = shift;

	# we have to do this ahead of time to make sure our WHERE
	# clause is computed correctly
	$self->set_inflated_columns($upd) if($upd);

	# short-circuit if we're not changed
	return $self if !$self->is_changed;

    if ( $self->optimistic_locking_strategy eq 'version' ) {
		# increment the version number but only if there are dirty
		# columns that are not being ignored by the optimistic
		# locking

		my %dirty_columns = $self->get_dirty_columns;

		delete(@dirty_columns{ @{ $self->optimistic_locking_ignore_columns || [] } });

		if(%dirty_columns){
			my $v_col = $self->optimistic_locking_version_column;

			# increment the version
			$self->set_column( $v_col, $self->_get_original_column($v_col) + 1 );
		}
    }

	# DBIx::Class::Row::update looks at this value, we'll precompute it
	# here to make sure it has all the elements we need (kind of a hack)
	$self->{_orig_ident} = $self->_optimistic_locking_ident_condition;

	my $return = $self->next::method();

	# flush the original values cache
	undef $self->{_opt_locking_orig_values};

	return $return;
}

sub _optimistic_locking_ident_condition {
	my $self = shift;
	my $ident_condition = $self->{_orig_ident} || $self->ident_condition;
	my $mode = $self->optimistic_locking_strategy;

	my $ignore_columns = $self->optimistic_locking_ignore_columns || [];
		
	if ( $mode eq 'dirty' ) {

        my %orig = %{$self->{_opt_locking_orig_values} || {}};
		delete($orig{$_}) foreach(@$ignore_columns);
        $ident_condition = {%orig, %$ident_condition };

	} elsif ( $mode eq 'version' ) {
		my $v_col = $self->optimistic_locking_version_column;
		$ident_condition->{ $v_col } = $self->_get_original_column( $v_col );

	} elsif ( $mode eq 'all' ) {

		my %orig = $self->_get_original_columns;
		delete($orig{$_}) foreach(@$ignore_columns);
		$ident_condition = { %orig, %$ident_condition };
	}

	return $ident_condition;
}


=head1 AUTHOR

Brian Phillips, C<< <bphillips at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dbix-class-optimisticlocking at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DBIx-Class-OptimisticLocking>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DBIx::Class::OptimisticLocking


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=DBIx-Class-OptimisticLocking>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DBIx-Class-OptimisticLocking>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DBIx-Class-OptimisticLocking>

=item * Search CPAN

L<http://search.cpan.org/dist/DBIx-Class-OptimisticLocking/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 Brian Phillips, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of DBIx::Class::OptimisticLocking
