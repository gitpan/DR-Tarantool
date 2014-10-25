#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

my $LE = $] > 5.01 ? '<' : '';

use constant PLAN       => 100;
use Test::More;
BEGIN {
    eval "use Coro";
    plan skip_all => "Coro isn't installed" if $@;
    plan tests => PLAN;
}

use Encode qw(decode encode);

BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool::StartTest';
    use_ok 'DR::Tarantool', ':constant';
    use_ok 'DR::Tarantool::CoroClient';
    use_ok 'File::Spec::Functions', 'catfile';
    use_ok 'File::Basename', 'dirname', 'basename';
    use_ok 'Coro';
    use_ok 'AnyEvent';
}

my $cfg_dir = catfile dirname(__FILE__), 'test-data';
ok -d $cfg_dir, 'directory with test data';
my $tcfg = catfile $cfg_dir, 'llc-easy2.cfg';
ok -r $tcfg, $tcfg;

my $tnt = run DR::Tarantool::StartTest( cfg => $tcfg );

my $spaces = {
    0   => {
        name            => 'first_space',
        fields  => [
            {
                name    => 'id',
                type    => 'NUM',
            },
            {
                name    => 'name',
                type    => 'UTF8STR',
            },
            {
                name    => 'key',
                type    => 'NUM',
            },
            {
                name    => 'password',
                type    => 'STR',
            },
            {
                name    => 'json',
                type    => 'JSON',
            }
        ],
        indexes => {
            0   => 'id',
            1   => 'name',
            2   => [ 'key', 'password' ],
        },
    }
};

SKIP: {
    unless ($tnt->started and !$ENV{SKIP_TNT}) {
        diag $tnt->log unless $ENV{SKIP_TNT};
        skip "tarantool isn't started", PLAN - 9;
    }

    my $client = DR::Tarantool::CoroClient->connect(
        port    => $tnt->primary_port,
        spaces  => $spaces
    );

    isa_ok $client => 'DR::Tarantool::CoroClient';
    is $client->last_code, undef, 'last_code';
    is $client->last_error_string, undef, 'last_error_string';
    ok $client->ping, '* ping';

    my $t = $client->insert(
        first_space => [ 1, 'привет', 2, 'test' ], TNT_FLAG_RETURN
    );

    isa_ok $t => 'DR::Tarantool::Tuple', '* insert tuple packed';
    is $t->id, 1, 'id';
    is $t->name, 'привет', 'name';
    is $t->key, 2, 'key';
    is $t->password, 'test', 'password';

    $t = $client->insert(
        first_space => [ 2, 'медвед', 3, 'test2' ], TNT_FLAG_RETURN
    );

    isa_ok $t => 'DR::Tarantool::Tuple', 'insert tuple packed';
    is $t->id, 2, 'id';
    is $t->name, 'медвед', 'name';
    is $t->key, 3, 'key';
    is $t->password, 'test2', 'password';


    $t = $client->call_lua('box.select' =>
        [ 0, 0, pack "L$LE" => 1 ], 'first_space');
    isa_ok $t => 'DR::Tarantool::Tuple', '* call tuple packed';
    is $t->id, 1, 'id';
    is $t->name, 'привет', 'name';
    is $t->key, 2, 'key';
    is $t->password, 'test', 'password';


    $t = $client->select(first_space => 1);
    isa_ok $t => 'DR::Tarantool::Tuple', '* select tuple packed';
    is $t->id, 1, 'id';
    is $t->name, 'привет', 'name';
    is $t->key, 2, 'key';
    is $t->password, 'test', 'password';

    $t = $client->select(first_space => 'привет', 'i1');
    isa_ok $t => 'DR::Tarantool::Tuple', 'select tuple packed (i1)';
    is $t->id, 1, 'id';
    is $t->name, 'привет', 'name';
    is $t->key, 2, 'key';
    is $t->password, 'test', 'password';

    $t = $client->select(first_space => [[2, 'test']], 'i2');
    isa_ok $t => 'DR::Tarantool::Tuple', 'select tuple packed (i2)';
    is $t->id, 1, 'id';
    is $t->name, 'привет', 'name';
    is $t->key, 2, 'key';
    is $t->password, 'test', 'password';

    $t = $client->update(first_space => 2 => [ name => set => 'привет1' ]);
    is $t, undef, '* update without flags';
    $t = $client->update(
        first_space => 2 => [ name => set => 'привет медвед' ], TNT_FLAG_RETURN
    );
    isa_ok $t => 'DR::Tarantool::Tuple', 'update with flags';
    is $t->name, 'привет медвед', '$t->name';


    $t = $client->insert(first_space => [1, 2, 3, 4, undef], TNT_FLAG_RETURN);
    is $t->json, undef, 'JSON insert: undef';

    $t = $client->insert(first_space => [1, 2, 3, 4, 22], TNT_FLAG_RETURN);
    is $t->json, 22, 'JSON insert: scalar';

    $t = $client->insert(first_space => [1, 2, 3, 4, 'тест'], TNT_FLAG_RETURN);
    is $t->json, 'тест', 'JSON insert: utf8 scalar';

    $t = $client->insert(
        first_space => [ 1, 2, 3, 4, { a => 'b' } ], TNT_FLAG_RETURN
    );
    isa_ok $t->json => 'HASH', 'JSON insert: hash';
    is $t->json->{a}, 'b', 'JSON insert: hash value';

    $t = $client->insert(
        first_space => [ 1, 2, 3, 4, { привет => 'медвед' } ], TNT_FLAG_RETURN
    );
    isa_ok $t->json => 'HASH', 'JSON insert: hash';
    is $t->json->{привет}, 'медвед', 'JSON insert: hash utf8 value';
    
    ok !eval {
        $client->insert(
            first_space => [ 1 .. 10 ], TNT_FLAG_RETURN | TNT_FLAG_ADD
        );
        1
    }, 'raise error';
    like $@, qr{Duplicate key exists|Tuple already exists}, 'error message';

    {
        local $client->{raise_error};
        ok eval {
            $client->insert(
                first_space => [ 1 .. 10 ], TNT_FLAG_RETURN | TNT_FLAG_ADD
            );
            1
        }, 'no raise error';
        like $client->last_error_string,
            qr{Duplicate key exists|Tuple already exists}, 'error message';
    }


    my $start = AnyEvent::now;
    my (@fibers, %tuples);
    for my $n (123 .. 129) {
        push @fibers => async {
            Coro::AnyEvent::sleep(rand);
            $tuples{ $n } =
                $client->insert(
                    'first_space',
                    [ $n, "тест $n", $n, "password $n" ],
                    TNT_FLAG_RETURN
                )
            ;
        };
    }

    $_->join for @fibers;

    cmp_ok AnyEvent::now() - $start, '<', '2', 'all processes were done async';

    for my $n (123 .. 129) {
        ok exists $tuples{$n}, 'result exists';
        isa_ok $tuples{$n} => 'DR::Tarantool::Tuple';
        is $tuples{$n}->id, $n, 'id';
        is $tuples{$n}->name, "тест $n", 'name';
        is $tuples{$n}->key, $n, 'key';
        is $tuples{$n}->password, "password $n", 'password';
    }
}
