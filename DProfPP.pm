package Devel::DProfPP;
use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = '1.0';
use constant DUMMY => sub {};
my $magic = "fOrTyTwO";

=head1 NAME

Devel::DProfPP - Parse C<Devel::DProf> output

=head1 SYNOPSIS

  use Devel::DProfPP;
  my $pp = Devel::DProfPP->new

  Devel::DProfPP->new(
        file    => "../tmon.out",
        enter   => sub { my ($self, $sub_name)  = shift;
                         my $topframe = ($self->stack)[-1];
                         print "\t" x $frame->height, $frame->sub_name;
                       }
  )->parse;

=head1 DESCRIPTION

This module takes the output file from L<Devel::DProf> (typically
F<tmon.out>) and parses it. By hooking subroutines onto the C<enter> and
C<leave> events, you can produce useful reports from the profiling data.

=head1 METHODS

=head2 new

    new(
        file    => $file,
        enter   => \&entersub_code,
        leave   => \&leavesub_code
    );

Creates a new parser object. All parameters are optional. See below
for more information about what the enter and leave hooks can do.

=cut

sub new {
    my $class = shift;
    my %args = @_;
    open my $fh, ($args{file} ||= "tmon.out") 
        or croak "Can't open $args{file}: $!";
    bless {
        fh    => $fh,
        enter => ($args{enter} || DUMMY),
        leave => ($args{leave} || DUMMY),
        stack => [],
        syms  => [],
        cum_times => {}
    }, $class;
}

=head2 parse

This parses the profiler output, running the enter and leave hooks, and
gathering information about subroutine timings.

=cut

sub parse {
    my $self = shift;
    $self->_parse_header;
    $self->_parse_body;
}

sub _parse_header {
    my $self = shift;
    my ($hz, $XS_VERSION, $over_utime, $over_stime, $over_rtime);
    my ($over_tests, $rrun_utime, $rrun_stime, $rrun_rtime, $total_marks);
    my $fh = $self->{fh};
    my $head = <$fh>;
    croak "This isn't really DProf output" unless $head =~ /$magic/;
    while (<$fh>) {
        last if /^PART2/;
        eval;
    }
    no strict 'refs';
    $self->{header} = {
        hz => $hz,
        XS_VERSION => $XS_VERSION,
        over_utime => $over_utime, over_stime => $over_stime,
        over_rtime => $over_rtime,
        over_tests => $over_tests,
        rrun_utime => $rrun_utime, rrun_stime => $rrun_stime,
        rrun_rtime => $rrun_rtime,
        total_marks => $total_marks,
    };
}

sub _parse_body {
    my $self = shift;
    my $fh = $self->{fh};

    while (<$fh>) {
        chomp;
        /^\@ (\d+) (\d+) (\d+)/ && do { $self->_add_times($1,$2,$3);     next;};
        /^\& (\d+) (\S+) (\S+)/ && do { $self->_introduce_sub($1,$2,$3); next;};
        /^\+ (\d+)/             && do { $self->_enter($1);               next;};
        /^\- (\d+)/             && do { $self->_leave($1);               next;};
        /^\+ & (\S+)/           && do { $self->_enter_named($1);         next;};
        /^\- & (\S+)/           && do { $self->_leave_named($1);         next;};
        /^\* (\d+)/             && do { $self->_goto($1);                next;};
        /^\/ (\d+)/             && do { $self->_die($1);                 next;};
        die "Didn't expect to see <$_> at this stage of play";
    }
}

sub _add_times {
    my ($self, @times) = @_;
    if (@{$self->{stack}} == 0) {
        # There's an interesting buglet in Devel::DProf/dprofpp that it
        # doesn't actually cater for timing the entire program. So
        # neither do we.
        return
    }
    $self->{stack}[-1]{times}[$_] += $times[$_] for 0..2;
    $self->{cum_times}{$self->{stack}[-1]{sub_name}}[$_] += $times[$_] for 0..2;
    for my $frame (@{$self->{stack}}) {
        $frame->{inc_times}[$_] += $times[$_] for 0..2;
    }
}

sub _introduce_sub {
    my ($self, $num, $pack, $sym) = @_;
    $self->{syms}[$num] = $pack."::".$sym;
}

=head2 stack

During the parsing run, C<$pp-C<gt>stack> will return a list of
C<Devel::DProfPP::Frame> objects. (See below) These can be examined for
the profile timings.

=cut

sub stack { @{$_[0]->{stack}} }

=head2 header

This returns a hash of the header information, whose keys are:

=over 3

=item hz

The number of clock cycles per second; the times are measured in cycles
and then converted into seconds later.

=item XS_VERSION

The version of the XS for the profiler.

=item over_utime

=item over_stime

=item over_rtime

The tested overhead of profiling, in user, system and real times. These
are in cycles.

=item over_tests

The number of samples that generated the above overhead; this is usually
2000. So divide C<over_utime> by C<over_tests> and you'll find the user
time overhead required to enter a subroutine. Take this off each
subroutine enter and leave event, and you'll have the "real" user time
of a subroutine call. C<Devel::DProfPP> doesn't do this for you.

=item rrun_utime

=item rrun_stime

=item rrun_rtime

The user, system and real times (in cycles) for the whole program run.

=cut

sub header { $_[0]->{header} }

=head1 HOOKS

The C<enter> and C<leave> hooks are called every time a subroutine is,
predictable, entered or left. In each case, the name of the subroutine
is passed in as a parameter to the hook, and everything else can be
accessed through the parser object and the stack.

=cut

sub _enter { 
    my ($self, $num) = @_;
    my $name = $self->{syms}[$num];
    die "Entering unknown subroutine $num" unless $name;
    $self->_enter_named($name);
}
sub _leave {
    my ($self, $num) = @_;
    my $name = $self->{syms}[$num];
    die "Leaving unknown subroutine $num" unless $name;
    $self->_leave_named($name);
}

sub _goto { 
    my ($self, $num) = @_;
    pop @{$self->{stack}};
    $self->_enter($num);
}
sub _die { goto &_leave }

sub _enter_named {
    my ($self, $sub) = @_;
    my $frame = Devel::DProfPP::Frame->new(
        parent => $self,
        sub_name => $sub,
        times => [0,0,0],
        inc_times => [0,0,0],
        height => ($#{$self->{stack}} + 1)
    );
    push @{$self->{stack}}, $frame;
    $self->{enter}->($sub);
}

sub _leave_named {
    my ($self, $sub) = @_;
    $self->{leave}->($sub);
    pop @{$self->{stack}};
}

1;

package Devel::DProfPP::Frame;

=head1 FRAME OBJECTS

The following methods are available on a C<Devel::DProfPP::Frame>
object:

=cut

sub new       { 
    my $class = shift;
    bless {@_}, $class;
}

=head2 times

=head2 inc_times

=head2 cum_times

These return the current execution time for a stack frame individually,
for the stack frame and all of its descendants, and for all instances
of this code.

These times are given in seconds, but B<DO NOT> include compensation for
subroutine enter/leave overheads. If you want to compensate for these,
subtract the appropriate overhead value from C<$pp-E<gt>header>.

=head2 height

The height of this stack frame - 1 for the first subroutine call on the
stack, 2 for the second, and so on.

=head2 sub_name

The fully qualified name of this subroutine.

=cut

sub times     { map { $_/($_[0]->{parent}{header}{hz})} @{$_[0]->{times}} }
sub inc_times { map { $_/($_[0]->{parent}{header}{hz})} @{$_[0]->{inc_times}} }
sub cum_times {
    my $self = shift;
    map { $_/($self->{parent}{header}{hz}) } 
    @{$self->{parent}{cum_times}{$self->{sub_name}} ||= [0,0,0]};
}
sub height     { $_[0]->{height} }
sub sub_name  { $_[0]->{sub_name} }

=head1 BUGS

Understanding how C<dprofpp>'s overhead compensation code works is Not
Easy and has meant that I haven't tried to apply overhead compensation
in this module. All the data's there if you want to do it yourself. The
numbers produced by C<Devel::DProf> are pseudorandom anyway, so this
omission should't make any real difference.

=head1 AUTHOR

Simon Cozens, C<simon@cpan.org>

=head1 LICENSE

You may distribute this module under the same terms as Perl itself.

=cut


1;
