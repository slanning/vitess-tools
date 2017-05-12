#!/usr/bin/env perl
#
# Bring down the Google Compute Engine,
# from the getting started tutorial at
# http://vitess.io/getting-started/
#
# Assumes:
# - you already have your Google Cloud SDK, etc. set up.
# - you run it in the example directory:
#   cd $HOME/go/src/github.com/youtube/vitess/examples/kubernetes/
#
# Run it like this:
#   gce-down.pl

use strict;
use warnings;
use feature 'say';

my $EXAMPLE_NAME = "example-$ENV{USER}";
my $BUCKET_NAME = "backup-bucket-$ENV{USER}";

foreach my $service (qw/guestbook vtgate vttablet vtctld etcd/) {
    say "stopping $service";
    `./$service-down.sh`;
}

say "tearing down cluster (takes a while)";
`gcloud container clusters delete $EXAMPLE_NAME`;
say "removing firewall rules";
`gcloud compute firewall-rules delete guestbook`;

# gsutil stat doesn't work on the bucket itself
unless (system("gsutil ls gs://$BUCKET_NAME")) {
    say "removing bucket $BUCKET_NAME";
    `gsutil -m rm -r gs://$BUCKET_NAME`;
}

say "ctrl-c the kubectl proxy, if that's running";
