# vim:ft=perl
use Test::More qw(no_plan);

use_ok("Devel::DProfPP");
my $thing;
my ($call_count, $leave_count);

my @times;

sub my_enter { $call_count++; }

sub my_leave { my $name = shift;
    $leave_count++;
    if ($name eq "main::_path") { @times = ($thing->stack)[-1]->cum_times; }
}

eval {$thing = new Devel::DProfPP; };
like ($@, qr/^Can't open/);
eval { $thing = new Devel::DProfPP(
    file => "t/tmon.out", 
    enter => \&my_enter, 
    leave => \&my_leave); };
isa_ok($thing, "Devel::DProfPP");
$thing->parse;
is_deeply($thing->{header}, {
    hz=>100,
    XS_VERSION=>'DProf 20000000.00_00',
    over_utime=>21, over_stime=>0, over_rtime=>46,
    over_tests=>10000,
    rrun_utime=>67, rrun_stime=>0, rrun_rtime=>135,
    total_marks=>7736              
}, "header is parsed correctly");
is($call_count, 3869, "Right number of enters");
is($leave_count, 3869, "Right number of leaves");
is_deeply(\@times, [0.21,0,0.36], "Correct cumulative times");
