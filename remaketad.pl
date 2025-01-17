#!/bin/perl
#
# You'll need to do "cpan Crypt::Rijndael" and "cpan Switch" in order to run this.
#
# I've commented out all the lines for using maketad to create a new TAD. 
# Just doing a bunch of testing stuff.

use strict;
use Crypt::Rijndael;
use Digest::SHA1 qw(sha1);

my $tad = $ARGV[0] or die "remaketad.pl <tad> <key>\n\nKey types:\nDSi:\n  dsi_dev\n  dsi_prod\n  dsi_debugger\n\nWii:\n  wii_dev\n  wii_prod\n  wii_vwii\n  wii_korea\n\nOther:\n  other_netcard\n";
my $key = $ARGV[1] or die "remaketad.pl <tad> <key>\n\nKey types:\nDSi:\n  dsi_dev\n  dsi_prod\n  dsi_debugger\n\nWii:\n  wii_dev\n  wii_prod\n  wii_vwii\n  wii_korea\n\nOther:\n  other_netcard\n";
my $outdir = substr($tad, 0, -4);
my $buf;

my $common_key;

use Switch;

switch($key) {
    case "dsi_dev" {
        $common_key = pack("H*", "a1604a6a7123b529ae8bec32c816fcaa");
    }
    case "dsi_prod" {
        $common_key = pack("H*", "af1bf516a807d21aea45984f04742861");
        next;
    }
    case "dsi_debugger" {
        $common_key = pack("H*", "a2fdddf2e423574ae7ed8657b5ab19d3");
        next;
    }
    case "wii_dev" {
        $common_key = pack("H*", "a1604a6a7123b529ae8bec32c816fcaa");
        next;
    }
    case "wii_prod" {
        $common_key = pack("H*", "ebe42a225e8593e448d9c5457381aaf7");
        next;
    }
    case "wii_vwii" {
        $common_key = pack("H*", "30bfc76e7c19afbb23163330ced7c28d");
        next;
    }
    case "wii_korea" {
        $common_key = pack("H*", "63b82bb4f4614e2e13f2fefbba4c9b7e");
        ;
    }
    case "other_netcard" {
        $common_key = pack("H*", "67458b6bc6237b3269983c6473483366");
        ;
    }
}

open(F, $tad) or die "cant open $tad\n";
binmode(F);
read(F, $buf, -s $tad);
close(F);

mkdir $outdir;


my $offset = 0;
my $size = 32;
my( $hdrSize, $tadType, $tadVersion, $certSize, 
	$crlSize, $ticketSize, $tmdSize, $contentSize, $metaSize)
		= unpack("Na2nNNNNNN", substr($buf, $offset, $size));
$offset += $size;

print <<__REPORT__;

hdrSize     $hdrSize
 tadType     $tadType
 tadVersion  $tadVersion
 certSize    $certSize
 crlSize     $crlSize
 ticketSize  $ticketSize
 tmdSize     $tmdSize
 contentSize $contentSize
 metaSize    $metaSize

__REPORT__

my $certOffset 		= &round_up($hdrSize, 64);
my $crlOffset  		= &round_up($certOffset 	+ $certSize, 	64);
my $ticketOffset 	= &round_up($crlOffset 		+ $crlSize, 	64);
my $tmdOffset  		= &round_up($ticketOffset 	+ $ticketSize, 	64);
my $contentOffset	= &round_up($tmdOffset 		+ $tmdSize, 	64);
my $metaOffset 		= &round_up($contentOffset	+ $contentSize, 64);
my $fileSize		= &round_up($metaOffset 	+ $metaSize, 	64);

die "file size is not expected size(=$fileSize)\n" if $fileSize != -s $tad;

my $ticket  = substr($buf, $ticketOffset, 	$ticketSize);
my $tmd     = substr($buf, $tmdOffset, 		$tmdSize);
my $content = substr($buf, $contentOffset, 	$contentSize);

&save_file("$outdir/$outdir.cert", 		substr($buf, $certOffset, 		$certSize));
&save_file("$outdir/$outdir.crl", 		substr($buf, $crlOffset, 		$crlSize));
&save_file("$outdir/$outdir.tik", 	$ticket);
&save_file("$outdir/$outdir.tmd", 		$tmd);
#&save_file("$outdir/content.bin", 	substr($buf, $contentOffset, 	$contentSize));
&save_file("$outdir/$outdir.meta",		substr($buf, $metaOffset, 		$metaSize));

print("Common key:             ");
print unpack("H*", $common_key), "\n";
my $title_key = &read_title_key($ticket);
my $rci = &read_content_info($tmd);

print("Decypted title key:     ");
print unpack("H*", $title_key), "\n";

my $offset = 0;
foreach my $i ( @$rci )
{
	my $size = &round_up($i->[3], 16);
	my $enc_content_x = substr($content, $offset, $size);
	my $content_x_iv = pack("n", $i->[1]) . pack("x14");
	my $dec_content_x = &dec_cbc($title_key, $content_x_iv, $enc_content_x);
	my $dec_content = substr($dec_content_x, 0, $i->[3]);
	my $hash = &sha1($dec_content);
	print("Content IV:             ");
	print unpack("H*", $content_x_iv), "\n";
	print("Content hash:           ");
	print unpack("H*", $hash), "\n";
	print("Expected hash:          ");
	print unpack("H*", $i->[4]), "\n";
	print((($hash eq $i->[4]) ? "OK": "hash mismatch"), "\n");
	#&save_file("$outdir/content_$i->[1].encrypted.bin", $enc_content_x);
	&save_file("$outdir/$outdir-$i->[1].app", $dec_content, $enc_content_x);


	$offset += &round_up($size, 64);
}

my $cfg = read_cfg($tmd);
save_cfg("$outdir/config.txt", $cfg);

print <<__REPORT__;

dataflg   $cfg->[0]
 titleid   $cfg->[1]
 groupid   $cfg->[2]
 major_ver $cfg->[3]
 minor_ver $cfg->[4]

__REPORT__

#maketad($tad, $cfg);
#system("/bin/rm -rf $outdir");


sub round_up
{	my( $x, $align ) = @_;

	return int( ($x + $align - 1)/$align ) * $align;
}

sub save_file
{	my( $name, $data ) = @_;

	open(OUT, ">$name") or die "cant open $name\n";
	binmode(OUT);
	print OUT $data;
	close(OUT);
}

sub read_content_info
{	my( $tmd ) = @_;
	my @ci = ();

	my $nContent = unpack("n", substr($tmd, 0x1DE, 2));

	for( my $i = 0; $i < $nContent; ++$i )
	{
		my( $cid, $idx, $type, $size, $hash )
			= unpack("Nnnx4Na20", substr($tmd, 0x1E4 + 36 * $i, 36));

		push @ci, [$cid, $idx, $type, $size, $hash];
	}

	return \@ci;
}

#sub maketad
#{	my( $tad, $cfg ) = @_;
#
#	my $maketad = "$ENV{TWL_IPL_RED_PRIVATE_ROOT}/tools/bin/maketad.updater.exe";
#	$tad =~ s/tad/updater.tad/;
#
#	my $option = "";
#	if( $cfg->[0] )
#	{
#		$option = "-d $cfg->[1] $cfg->[2] $cfg->[3] $tad -v $cfg->[4]";
#	} else {
#		$option = "-v $cfg->[4]";
#	}
#
#	my $cmd = "$maketad $outdir/content_0.bin $option -s -o $tad";
#	system("/bin/echo $cmd");
#	system("$cmd");
#}

sub read_cfg
{	my( $tmd ) = @_;

	my( $titleid_h, $titleid_l ) = unpack("NN", substr($tmd, 0x18C, 8));
	my $groupid  = sprintf("%04X", unpack("n", substr($tmd, 0x198, 2)));
	my( $major_ver, $minor_ver ) = unpack("CC", substr($tmd, 0x1DC, 2));

	my $titleid  = sprintf("%08X%08X", $titleid_h, $titleid_l);
	my $dataflg  = ($titleid_h & 0x08) >> 3;

	return [ $dataflg, $titleid, $groupid, $major_ver, $minor_ver ]
}

sub save_cfg
{	my( $name, $cfg ) = @_;

	open(OUT, ">$name") or die "cant open $name\n";
	print OUT sprintf("dataflg = $cfg->[0]\n");
	print OUT sprintf("titleid = $cfg->[1]\n");
	print OUT sprintf("groupid = $cfg->[2]\n");
	print OUT sprintf("major_ver = $cfg->[3]\n");
	print OUT sprintf("minor_ver = $cfg->[4]\n");
	close(OUT);
}

sub read_title_key
{	my( $ticket ) = @_;

	my $enc_title_key = substr($ticket, 0x1BF, 16);
	my $title_key_iv = substr($ticket, 0x1DC, 8) . pack("x8");
	print("Encypted title key:     ");
	print unpack("H*", $enc_title_key), "\n";
	print("Encypted title key IV:  ");
	print unpack("H*", $title_key_iv), "\n";
	return &dec_cbc($common_key, $title_key_iv, $enc_title_key);
}

sub dec_cbc
{	my( $key, $iv, $data ) = @_;

	my $cbc = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_CBC);
	$cbc->set_iv($iv);
	return $cbc->decrypt($data);
}
