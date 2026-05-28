use Test::More;
BEGIN { SKIP: { eval { require Test::Warnings; 1; } or skip($@, 1); } }
BEGIN { eval { require JSON::PP; 1; } or plan(skip_all => $@); JSON::PP->import(); }
BEGIN { eval { require 'ddclient'; } or BAIL_OUT($@); }
use ddclient::t::HTTPD;
use ddclient::t::Logger;

httpd_required();

ddclient::load_json_support('whm');

my $j = ['Content-Type' => 'application/json'];

sub dump_resp {
    my (%args) = @_;
    my $zone    = $args{zone}    // 'example.com';
    my $records = $args{records} // [];
    my $serial  = $args{serial}  // 2024010101;
    my @recs = (
        {type => 'SOA', serial => $serial},
        @$records,
    );
    return encode_json({
        data     => {zone => [{record => \@recs}]},
        metadata => {result => 1, reason => 'Done.'},
    });
}

sub a_record {
    my ($name, $ip, $line, $ttl) = @_;
    return {name => $name, type => 'A', address => $ip, Line => $line, ttl => $ttl // 300};
}

sub aaaa_record {
    my ($name, $ip, $line, $ttl) = @_;
    return {name => $name, type => 'AAAA', address => $ip, Line => $line, ttl => $ttl // 300};
}

sub ok_resp {
    return encode_json({metadata => {result => 1, reason => 'Done.'}});
}

httpd()->run();

my @test_cases = (
    {
        desc => 'IPv4 success, no existing record (create)',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
        }},
        responses => [
            [200, $j, [dump_resp(zone => 'example.com', records => [])]],
            [200, $j, [ok_resp()]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv4' => 'good',
            'ipv4'        => '192.0.2.1',
            'mtime'       => $ddclient::now,
        }},
        wantlogs => [
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv4.*192\.0\.2\.1/},
        ],
        check_reqs => sub {
            my @reqs = @_;
            is(scalar(@reqs), 2, '2 requests: GET dumpzone + POST addzonerecord');
            is($reqs[0]->method(), 'GET',  'first request is GET');
            like($reqs[0]->uri()->path(), qr{/json-api/dumpzone}, 'GET path is dumpzone');
            like($reqs[0]->uri()->query(), qr{domain=example\.com}, 'query has domain');
            is($reqs[1]->method(), 'POST', 'second request is POST');
            like($reqs[1]->uri()->path(), qr{/json-api/addzonerecord}, 'POST to addzonerecord');
            my $body = $reqs[1]->content();
            like($body, qr/type=A/,              'body has type=A');
            like($body, qr/address=192\.0\.2\.1/, 'body has correct address');
            like($body, qr/name=host\.example\.com\./, 'body has fqdn name with trailing dot');
        },
    },
    {
        desc => 'IPv4 success, existing record (update)',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.2',
        }},
        responses => [
            [200, $j, [dump_resp(
                zone    => 'example.com',
                serial  => 2024010101,
                records => [a_record('host.example.com.', '192.0.2.1', 10)],
            )]],
            [200, $j, [ok_resp()]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv4' => 'good',
            'ipv4'        => '192.0.2.2',
            'mtime'       => $ddclient::now,
        }},
        wantlogs => [
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv4.*192\.0\.2\.2/},
        ],
        check_reqs => sub {
            my @reqs = @_;
            is(scalar(@reqs), 2, '2 requests: GET dumpzone + POST editzonerecord');
            is($reqs[1]->method(), 'POST', 'second request is POST');
            like($reqs[1]->uri()->path(), qr{/json-api/editzonerecord}, 'POST to editzonerecord');
            my $body = $reqs[1]->content();
            like($body, qr/line=10/,              'body has correct line number');
            like($body, qr/serial=2024010101/,    'body has SOA serial');
            like($body, qr/address=192\.0\.2\.2/, 'body has new address');
        },
    },
    {
        desc => 'IPv6 success, no existing record (create)',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv6 => '2001:db8::1',
        }},
        responses => [
            [200, $j, [dump_resp(zone => 'example.com', records => [])]],
            [200, $j, [ok_resp()]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv6' => 'good',
            'ipv6'        => '2001:db8::1',
            'mtime'       => $ddclient::now,
        }},
        wantlogs => [
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv6.*2001:db8::1/},
        ],
        check_reqs => sub {
            my @reqs = @_;
            is(scalar(@reqs), 2, '2 requests for IPv6');
            like($reqs[1]->uri()->path(), qr{/json-api/addzonerecord}, 'POST to addzonerecord');
            my $body = $reqs[1]->content();
            like($body, qr/type=AAAA/,            'body has type=AAAA');
            like($body, qr/address=2001%3Adb8%3A%3A1|address=2001:db8::1/, 'body has IPv6 address');
        },
    },
    {
        desc => 'IPv6 success, existing record (update)',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv6 => '2001:db8::2',
        }},
        responses => [
            [200, $j, [dump_resp(
                zone    => 'example.com',
                serial  => 2024010101,
                records => [aaaa_record('host.example.com.', '2001:db8::1', 12)],
            )]],
            [200, $j, [ok_resp()]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv6' => 'good',
            'ipv6'        => '2001:db8::2',
            'mtime'       => $ddclient::now,
        }},
        wantlogs => [
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv6.*2001:db8::2/},
        ],
        check_reqs => sub {
            my @reqs = @_;
            like($reqs[1]->uri()->path(), qr{/json-api/editzonerecord}, 'POST to editzonerecord');
            my $body = $reqs[1]->content();
            like($body, qr/line=12/, 'body has AAAA record line number');
        },
    },
    {
        desc => 'both IPv4 and IPv6 success',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
            wantipv6 => '2001:db8::1',
        }},
        responses => [
            # One dumpzone for both IPs (fetched once)
            [200, $j, [dump_resp(zone => 'example.com', records => [])]],
            [200, $j, [ok_resp()]],  # addzonerecord for A
            [200, $j, [ok_resp()]],  # addzonerecord for AAAA
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv4' => 'good', 'ipv4' => '192.0.2.1',
            'status-ipv6' => 'good', 'ipv6' => '2001:db8::1',
            'mtime'       => $ddclient::now,
        }},
        wantlogs => [
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv4/},
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv6/},
        ],
        check_reqs => sub {
            my @reqs = @_;
            is(scalar(@reqs), 3, '3 requests: GET dumpzone + POST A + POST AAAA');
            is($reqs[0]->method(), 'GET',  'first is GET');
            is($reqs[1]->method(), 'POST', 'second is POST A');
            is($reqs[2]->method(), 'POST', 'third is POST AAAA');
        },
    },
    {
        desc => 'custom TTL is sent',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            ttl      => 600,
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
        }},
        responses => [
            [200, $j, [dump_resp(zone => 'example.com', records => [])]],
            [200, $j, [ok_resp()]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv4' => 'good',
            'ipv4'        => '192.0.2.1',
            'mtime'       => $ddclient::now,
        }},
        wantlogs => [
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv4/},
        ],
        check_reqs => sub {
            my @reqs = @_;
            my $body = $reqs[1]->content();
            like($body, qr/ttl=600/, 'body has custom TTL');
        },
    },
    {
        desc => 'Basic Auth credentials sent correctly',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'supersecret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
        }},
        responses => [
            [200, $j, [dump_resp(zone => 'example.com', records => [])]],
            [200, $j, [ok_resp()]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv4' => 'good',
            'ipv4'        => '192.0.2.1',
            'mtime'       => $ddclient::now,
        }},
        wantlogs => [
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv4/},
        ],
        check_reqs => sub {
            my @reqs = @_;
            ## "root:supersecret" in Base64 is cm9vdDpzdXBlcnNlY3JldA==
            is($reqs[0]->header('Authorization'),
               'Basic cm9vdDpzdXBlcnNlY3JldA==',
               'Authorization header has correct Basic credentials');
        },
    },
    {
        desc => 'dumpzone API failure (metadata.result != 1)',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
        }},
        responses => [
            [200, $j, [encode_json({
                data     => {zone => []},
                metadata => {result => 0, reason => 'Zone not found'},
            })]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv4' => 'failed',
            'status-ipv6' => 'failed',
        }},
        wantlogs => [
            {label => 'FAILED', ctx => ['host.example.com'], msg => qr/Zone not found/},
        ],
    },
    {
        desc => 'HTTP 401 on dumpzone',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'baduser',
            password => 'badpass',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
        }},
        responses => [
            [401, $j, [encode_json({metadata => {result => 0, reason => 'Unauthorized'}})]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv4' => 'failed',
            'status-ipv6' => 'failed',
        }},
        wantlogs => [
            {label => 'FAILED', ctx => ['host.example.com'], msg => qr/API error 401/},
        ],
    },
    {
        desc => 'HTTP 500 on editzonerecord',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
        }},
        responses => [
            [200, $j, [dump_resp(
                zone    => 'example.com',
                records => [a_record('host.example.com.', '192.0.2.99', 10)],
            )]],
            [500, $j, [encode_json({metadata => {result => 0, reason => 'Internal error'}})]],
        ],
        wantrecap => {'host.example.com' => {'status-ipv4' => 'failed'}},
        wantlogs => [
            {label => 'FAILED', ctx => ['host.example.com'], msg => qr/API error 500/},
        ],
    },
    {
        desc => 'editzonerecord API failure (metadata.result != 1)',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
        }},
        responses => [
            [200, $j, [dump_resp(
                zone    => 'example.com',
                records => [a_record('host.example.com.', '192.0.2.99', 10)],
            )]],
            [200, $j, [encode_json({metadata => {result => 0, reason => 'Record locked'}})]],
        ],
        wantrecap => {'host.example.com' => {'status-ipv4' => 'failed'}},
        wantlogs => [
            {label => 'FAILED', ctx => ['host.example.com'], msg => qr/Record locked/},
        ],
    },
    {
        desc => 'correct domain param sent in dumpzone query',
        cfg => {'host.example.com' => {
            protocol => 'whm',
            login    => 'root',
            password => 'secret',
            zone     => 'example.com',
            server   => httpd()->endpoint(),
            wantipv4 => '192.0.2.1',
        }},
        responses => [
            [200, $j, [dump_resp(zone => 'example.com', records => [])]],
            [200, $j, [ok_resp()]],
        ],
        wantrecap => {'host.example.com' => {
            'status-ipv4' => 'good',
            'ipv4'        => '192.0.2.1',
            'mtime'       => $ddclient::now,
        }},
        wantlogs => [
            {label => 'SUCCESS', ctx => ['host.example.com'], msg => qr/IPv4/},
        ],
        check_reqs => sub {
            my @reqs = @_;
            like($reqs[0]->uri()->query(), qr/domain=example\.com/, 'query has correct domain');
            like($reqs[0]->uri()->query(), qr/api\.version=1/,      'query has api.version=1');
        },
    },
);

for my $tc (@test_cases) {
    subtest($tc->{desc} => sub {
        local $ddclient::globals{debug}   = 1;
        local $ddclient::globals{verbose} = 1;
        local %ddclient::config  = %{$tc->{cfg}};
        local %ddclient::recap;

        httpd()->reset(@{$tc->{responses}});

        my $l = ddclient::t::Logger->new($ddclient::_l, qr/^(?:WARNING|FATAL|SUCCESS|FAILED)$/);
        {
            local $ddclient::_l = $l;
            ddclient::nic_whm_update(undef, sort(keys(%{$tc->{cfg}})));
        }

        my @reqs = httpd()->reset();

        is_deeply(\%ddclient::recap, $tc->{wantrecap}, 'recap matches')
            or diag(ddclient::repr(Values => [\%ddclient::recap, $tc->{wantrecap}],
                                   Names  => ['*got', '*want']));

        subtest('logs' => sub {
            my @got  = @{$l->{logs}};
            my @want = @{$tc->{wantlogs} // []};
            for my $i (0..$#want) {
                last if $i >= @got;
                subtest("log $i" => sub {
                    is($got[$i]{label}, $want[$i]{label}, 'label');
                    is_deeply($got[$i]{ctx}, $want[$i]{ctx}, 'context');
                    like($got[$i]{msg}, $want[$i]{msg}, 'message');
                });
            }
            my @unexpected = @got[@want..$#got];
            ok(@unexpected == 0, 'no unexpected logs')
                or diag(ddclient::repr(\@unexpected, Names => ['*unexpected']));
            my @missing = @want[@got..$#want];
            ok(@missing == 0, 'no missing logs')
                or diag(ddclient::repr(\@missing, Names => ['*missing']));
        });

        $tc->{check_reqs}->(@reqs) if $tc->{check_reqs};
    });
}

done_testing();
