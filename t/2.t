# vim:ft=perl
use Test::More qw(no_plan);
use Data::Dumper;

use_ok("Devel::DProfPP");

my $pp = Devel::DProfPP->new(file => 't/not_tmon.out', );
eval {$pp->parse();};
like($@, qr/^This isn't really DProf output/, "Test parsing an empty file");

$pp = Devel::DProfPP->new(file => 't/not_tmon2.out', );
eval {$pp->parse();};
like($@, qr/^This isn't really DProf output/, "Test parsing a non-tmon.out file");

$pp = Devel::DProfPP->new(file => 't/tmon_bad.out', );
eval {$pp->parse();};
like($@, qr/^Didn't expect to see/, "Test parsing a bad tmon.out file");

eval { $pp->_enter(5); };
like($@, qr/^Entering unknown subroutine/, 'Testing entering an unknown subroutine');

eval { $pp->_leave(5); };
like($@, qr/^Leaving unknown subroutine/, 'Testing leaving an unknown subroutine');
