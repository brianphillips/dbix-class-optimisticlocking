package DBIx::Class::OptimisticLocking;

use warnings;
use strict;

use base 'DBIx::Class';


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

	package My::Class;

	use base qw/DBIx::Class/;

	__PACKAGE__->load_components(qw/OptimisticLocking Core/);

=head1 CONFIGURATION

=head2 optimistic_locking_mode

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
L<optimistic_locking_version_column>).  The C<version> column will also
be incremented on each update as well.

=item * all

When issuing an update, the C<WHERE> clause of the update will include
a check on each column in the object regardless of whether they were
updated or not.

=item * none (or any other value)

This turns off the functionality of this component.  But why would you
load it if you don't need it? :-)

=back

=head2 optimistic_locking_insignificant_dirty_columns

Occassionally you may elect to ignore certain columns that are not
significant enough to detect colisions and cause the update to fail.
For instance, if you have a timestamp column, you may want to add
that to this list so that it is ignored when generating the C<UPDATE>
where clause for the update.

=head2 optimistic_locking_version_column

If you are using 'version' as your L<optimistic_locking_mode>, you can
optionally specify a different name for the column used for version
tracking.  If an alternate name is not passed, the component will look
for a column named C<version>.

=cut

__PACKAGE__->mk_classdata(optimistic_locking_mode => 'dirty');
__PACKAGE__->mk_classdata('optimistic_locking_insignificant_dirty_columns');
__PACKAGE__->mk_classdata(optimistic_locking_version_column => 'version');

=head1 METHODS

=head2 get_original_columns

Corresponds to L<DBIx::Class::Row/get_columns> except that the values
returned reflect the original state of the object.

=cut


sub get_original_columns {
	my $self = shift;
	my %columns = ( $self->get_columns, %{ $self->{_opt_locking_orig_values} || {} } );
	return %columns;
}

=head2 get_original_column

Corresponds to L<DBIx::Class::Row/get_column> except that the value
returned reflects the original state of the object.

=cut

sub get_original_column {
	my $self = shift;
	my $column = shift;
	my %columns = $self->get_original_columns;
	return exists $columns{$column} ? $columns{$column} : ();
}

sub set_column {
	my $self = shift;
	my ($column) = @_;

    my $track_original_values = (
        (
                 $self->optimistic_locking_mode eq 'dirty'
              || $self->optimistic_locking_mode eq 'all'
        )
        && !$self->is_column_changed($column)
    );

	# save off the original if this is the first time the column has been changed
	if($track_original_values){

            $self->{_opt_locking_orig_values}->{$column} = $self->get_column($column);
	}
	return $self->next::method(@_);
}


sub update {
	my $self = shift;
	my $upd = shift;

	# we have to do this ahead of time to make sure our WHERE
	# clause is computed correctly
	$self->set_inflated_columns($upd) if($upd);

	# short-circuit if we're not changed
	return $self if !$self->is_changed;

    if ( $self->optimistic_locking_mode eq 'version' ) {
        my $v_col = $self->optimistic_locking_version_column;

        # increment the version
        $self->set_column( $v_col, $self->get_original_column($v_col) + 1 );
    }

	# DBIx::Class::Row::update looks at this value, we'll precompute it
	# here to make sure it has all the elements we need (kind of a hack)
	$self->{_orig_ident} = $self->_optimistic_locking_ident_condition;

	my $return = $self->next::method(@_);

	# flush the original values cache
	undef $self->{_opt_locking_orig_values};

	return $return;
}

sub _optimistic_locking_ident_condition {
	my $self = shift;
	my $ident_condition = $self->{_orig_ident} || $self->ident_condition;
	my $mode = $self->optimistic_locking_mode;

	# also check to see if this column is considered insignificant (default behavior: every column is significant)
	my $insignificant = $self->optimistic_locking_insignificant_dirty_columns || [];
	
	# also check to see if this column is considered insignificant (default behavior: every column is significant)
	my $insignificant = $self->optimistic_locking_insignificant_dirty_columns || [];
		
	if ( $mode eq 'dirty' ) {

        my %orig = %{$self->{_opt_locking_orig_values} || {}};
		delete($orig{$_}) foreach(@$insignificant);
        $ident_condition = {%orig, %$ident_condition };

	} elsif ( $mode eq 'version' ) {

		my $v_col = $self->optimistic_locking_version_column;
		$ident_condition->{ $v_col } = $self->get_column( $v_col );

	} elsif ( $mode eq 'all' ) {

		$ident_condition = { $self->get_original_columns, %$ident_condition };

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
