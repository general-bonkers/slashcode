#!/usr/bin/perl -w

use strict;

use vars qw( %task $me );

# Remember that timespec goes by the database's time, which should be
# GMT if you installed everything correctly.  So 6:07 AM GMT is a good
# sort of midnightish time for the Western Hemisphere.  Adjust for
# your audience and admins.
$task{$me}{timespec} = '7 6 * * *';
$task{$me}{timespec_panic_2} = ''; # if major panic, dailyStuff can wait
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my($stats, $backupdb);

	my $statsSave = getObject('Slash::Stats');
	if ($constants->{backup_db_user}) {
		$stats = getObject('Slash::Stats', $constants->{backup_db_user});
		$backupdb = getObject('Slash::DB', $constants->{backup_db_user});
	} else {
		$stats = getObject('Slash::Stats');
		$backupdb = $slashdb;
	}

	unless($stats) {
		slashdLog('No database to run adminmail against');
		return;
	}

	slashdLog('Send Admin Mail Begin');
	my $count = $stats->countDaily();

	# homepage hits are logged as either '' or 'shtml'
	$count->{'index'}{'index'} += delete $count->{'index'}{''};
	$count->{'index'}{'index'} += delete $count->{'index'}{'shtml'};
	# these are 404s
	delete $count->{'index.html'};

	my $sdTotalHits = $stats->getVar('totalhits', 'value');
	$sdTotalHits = $sdTotalHits + $count->{'total'};

	my $admin_clearpass_warning = '';
	if ($constants->{admin_check_clearpass}) {
		my $clear_admins = $stats->getAdminsClearpass();
		if ($clear_admins and keys %$clear_admins) {
			for my $admin (sort keys %$clear_admins) {
				$admin_clearpass_warning .=
					"$admin $clear_admins->{$admin}{value}\n";
			}
		}
		if ($admin_clearpass_warning) {
			$admin_clearpass_warning = <<EOT;


WARNING: The following admins accessed the site with their passwords,
in cookies, sent in the clear.  They have been told to change their
passwords but have not, as of the generation of this email.  They
need to do so immediately.

$admin_clearpass_warning
EOT
		}
	}

	my $accesslog_rows = $stats->sqlCount('accesslog');
	my $formkeys_rows = $stats->sqlCount('formkeys');
	my $modlog_rows = $stats->sqlCount('moderatorlog');
	my $metamodlog_rows = $stats->sqlCount('metamodlog');

	my $mod_points = $stats->getPoints;
	my @yesttime = localtime(time-86400);
	my $yesterday = sprintf "%4d-%02d-%02d", 
		$yesttime[5] + 1900, $yesttime[4] + 1, $yesttime[3];
	my $used = $stats->countModeratorLog($yesterday);
	my $modlog_hr = $stats->countModeratorLogHour($yesterday);
	my $distinct_comment_ipids = $stats->getCommentsByDistinctIPID($yesterday);
	my $submissions = $stats->countSubmissionsByDay($yesterday);
	my $submissions_comments_match = $stats->countSubmissionsByCommentIPID($yesterday, $distinct_comment_ipids);
	my $modlog_total = $modlog_hr->{1}{count} + $modlog_hr->{-1}{count};

	my $comments = $stats->countCommentsDaily($yesterday);

	my $uniq_comment_users = $stats->countDailyByOPDistinctIPID('comments', $yesterday);
	my $uniq_article_users = $stats->countDailyByOPDistinctIPID('article', $yesterday);
	my $uniq_palm_users = $stats->countDailyByOPDistinctIPID('palm', $yesterday);
	my $comment_page_views = $stats->countDailyByOP('comments',$yesterday);
	my $article_page_views = $stats->countDailyByOP('article',$yesterday);
	my $palm_page_views = $stats->countDailyByOP('palm',$yesterday);

	$statsSave->createStatDaily($yesterday, "total", $count->{total});
	$statsSave->createStatDaily($yesterday, "unique", $count->{unique});
	$statsSave->createStatDaily($yesterday, "unique_users", $count->{unique_users});
	$statsSave->createStatDaily($yesterday, "comments", $comments);
	$statsSave->createStatDaily($yesterday, "homepage", $count->{index}{index});
	$statsSave->createStatDaily($yesterday, "journals", $count->{journals});
	$statsSave->createStatDaily($yesterday, "distinct_comment_ipids", $distinct_comment_ipids);
	$statsSave->createStatDaily($yesterday, "uniq_comment_users", $uniq_comment_users);
	$statsSave->createStatDaily($yesterday, "uniq_article_users", $uniq_article_users);
	$statsSave->createStatDaily($yesterday, "uniq_palm_users", $uniq_palm_users);
	$statsSave->createStatDaily($yesterday, "comment_page_views", $comment_page_views);
	$statsSave->createStatDaily($yesterday, "article_page_views", $article_page_views);
	$statsSave->createStatDaily($yesterday, "palm_page_views", $palm_page_views);

	my @numbers = (
		$count->{total},
		$count->{unique},
		$count->{unique_users},
		$accesslog_rows,
		$formkeys_rows,
		$modlog_rows,
		$metamodlog_rows,
			($modlog_rows  ? $metamodlog_rows/$modlog_rows	: 0),
		$mod_points,
		$modlog_total,
			($mod_points   ? $modlog_total*100/$mod_points	: 0),
			($comments     ? $modlog_total*100/$comments	: 0),
		$modlog_hr->{-1}{count},
			($modlog_total ? $modlog_hr->{-1}{count}*100
						/$modlog_total		: 0),
		$modlog_hr->{1}{count},
			($modlog_total ? $modlog_hr->{1}{count}*100
						/$modlog_total		: 0),
		$comments,
		scalar(@$distinct_comment_ipids),
		$uniq_comment_users,
		$uniq_article_users,
		$uniq_palm_users,
		$comment_page_views,
		$article_page_views,
		$palm_page_views,
		$count->{journals},
		$submissions,
			($submissions ? $submissions_comments_match*100
						/$submissions		: 0),
		$sdTotalHits,
		$count->{index}{index},
	);
	my $email = sprintf(<<"EOT", @numbers);
$constants->{sitename} Stats for yesterday

        total: %8d
       unique: %8d
        users: %8d
$admin_clearpass_warning
    accesslog: %8d rows total
     formkeys: %8d rows total
       modlog: %8d rows total
   metamodlog: %8d rows total (%.1fx modlog)
   mod points: %8d in pool
   used total: %8d yesterday (%.1f%% of pool, %.1f%% of comments)
      used -1: %8d yesterday (%.1f%%)
      used +1: %8d yesterday (%.1f%%)
     comments: %8d posted yesterday
        IPIDS: %8d distinct IPIDS posted comments
             : %8d distinct IPIDS used comments
             : %8d distinct IPIDS used articles
             : %8d distinct IPIDS used palm pages
    pageviews: %8d for comments
             : %8d for articles
             : %8d for palm
             : %8d for journals
  submissions: %8d submissions
 sub/comments: %8.1f%% of the submissions came from comment posters from this day

   total hits: %8d
     homepage: %8d
      indexes
EOT

	for (sort {lc($a) cmp lc($b)} keys %{$count->{index}}) {
		$email .= "\t   $_=$count->{index}{$_}\n";
		$statsSave->createStatDaily($yesterday, "index_$_", $count->{index}{$_});
	}

	$email .= "\n-----------------------\n";


	for my $key (sort { $count->{'articles'}{$b} <=> $count->{'articles'}{$a} } keys %{$count->{'articles'}}) {
		my $value = $count->{'articles'}{$key};

 		my $story = $backupdb->getStory($key, ['title', 'uid']);

		$email .= sprintf("%6d %-16s %-30s by %s\n",
			$value, $key, substr($story->{'title'}, 0, 30),
			($slashdb->getUser($story->{uid}, 'nickname') || $story->{uid})
		) if $story->{'title'} && $story->{uid} && $value > 100;
	}

	$email .= "\n-----------------------\n";
	$email .= `$constants->{slashdir}/bin/tailslash -u $virtual_user -y today`;

	$email .= "\n-----------------------\n";

	# Send a message to the site admin.
	for (@{$constants->{stats_reports}}) {
		sendEmail($_, "$constants->{sitename} Stats Report", $email, 'bulk');
	}
	slashdLog('Send Admin Mail End');

	return ;
};

1;

