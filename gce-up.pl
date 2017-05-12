#!/usr/bin/env perl
#
# Bring up the Google Compute Engine,
# from the getting started tutorial at
# http://vitess.io/getting-started/
# Assumes:
# - you already have your Google Cloud SDK, etc. set up.
# - you run it in the example directory:
#   cd $HOME/go/src/github.com/youtube/vitess/examples/kubernetes/
#   If you didn't already, run this in that directory:
#      ./configure.sh
#
# Run it like this:
#   gce-up.pl us-east1-d 3
# where 3 is the number of nodes, europe-west1-b is the GCE region

use strict;
use warnings;
use feature 'say';

sub pause {
    say "ready?";
    <>;
}

die "usage: ./gce-up.pl europe-west1-b 3\n"
  unless @ARGV == 2 and $ARGV[1] =~ /\A\d+\z/a;
my $COMPUTE_ZONE = shift @ARGV;
my $NUM_NODES    = shift @ARGV;

my $EXAMPLE_NAME = "example-$ENV{USER}";
my $BUCKET_NAME  = "backup-bucket-$ENV{USER}";

say "browse to https://console.cloud.google.com\n(make sure it's your booking.com account)";

say "setting compute zone to $COMPUTE_ZONE";
`gcloud config set compute/zone $COMPUTE_ZONE`;

say "creating container cluster (can take a while...)";
`gcloud container clusters create $EXAMPLE_NAME --machine-type n1-standard-4 --num-nodes $NUM_NODES --scopes storage-rw`;

# gsutil stat doesn't work on the bucket itself
if (system("gsutil ls gs://$BUCKET_NAME")) {
    `gsutil mb gs://backup-bucket-$ENV{USER}`;
}
else {
    say "kept bucket $BUCKET_NAME";
}

say "starting etcd (topology service of the cluster)";
`./etcd-up.sh`;

sleep 5;

say "starting vtctld (web interface to inspect the cluster)";
`./vtctld-up.sh`;
say "\nDO THIS in a separate terminal:\nkubectl proxy --port=8001\n\nand OPEN these in a browser:\nhttp://localhost:8001/api/v1/proxy/namespaces/default/services/vtctld:web/\nhttp://localhost:8001/ui";

say "\nwill start vttablets (mysqld servers, can take a while)";
pause();
`./vttablet-up.sh`;

# how to check more properly?
say "sleeping a bit for the tablets to come up...";
sleep 60;

pause();

while (1) {
    say "checking until all tablets are up";
    # they shouldn't be in "restore" state
    my @l = grep { /^test-.+(?:replica|rdonly)/ } split(/\n/, `./kvtctl.sh ListAllTablets test`);

    if (@l) {
        say for @l;

        if (@l == 5) {  # sufficient, does it need a certain status?
            say "all 5 tablets are up";
            last;
        }
        else {
            printf("%s tablets so far\n", scalar(@l));
        }
    }
    else {
        say "nothing up yet";
    }

    sleep 5;
}

say "setting shard master tablet";
`./kvtctl.sh InitShardMaster -force test_keyspace/0 test-0000000100`;

say "creating a test table";
`./kvtctl.sh ApplySchema -sql "\$(cat create_test_table.sql)" test_keyspace`;

say "taking a backup";
`./kvtctl.sh Backup test-0000000104`;

say "making schema visible";
`./kvtctl.sh RebuildVSchemaGraph`;

say "starting vtgate (routes client to vttablet)";
`./vtgate-up.sh`;

say "starting guestbook";
`./guestbook-up.sh`;
`gcloud compute firewall-rules create guestbook --allow tcp:80`;

say "waiting for external IP...";

# external IP starts out as <pending>
my $extip = '<pending>';
while ($extip !~ /\A\d+\.\d+\.\d+\.\d+\z/a) {
    sleep 5;
    my @l = split(/\n/, `kubectl get service guestbook`);
    (undef, undef, $extip) = split/\s+/, $l[1];

    say "external is $extip";
}
say "browse http://$extip";
