#!/usr/bin/env perl
# $Id$
# ======================================================================
# NCBI BLAST jDispatcher REST web service Perl client
#
# Tested with:
#   LWP 5.79, XML::Simple 2.12 and Perl 5.8.3
#   LWP 5.805, XML::Simple 2.14 and Perl 5.8.7
#   LWP 5.820 and Perl 5.10.0 (Ubuntu 9.04)
#
# See:
# http://www.ebi.ac.uk/Tools/Webservices/tutorials/perl
# ======================================================================
# Base URL for service
my $baseUrl = 'http://wwwdev.ebi.ac.uk/Tools/jdispatcher/services/rest/ncbiblast';

# Enable Perl warnings
use strict;
use warnings;

# Load libraries
use LWP;
use XML::Simple;
use Getopt::Long qw(:config no_ignore_case bundling);
use File::Basename;
use Data::Dumper;

# Set interval for checking status
my $checkInterval = 3;

# Output level
my $outputLevel = 1;

# Process command-line options
my $numOpts = scalar(@ARGV);
my %params  = ( 'debugLevel' => 0 );

# Default parameter values (should get these from the service)
my %tool_params = (
	'program'    => 'blastp',
	'stype'      => 'protein',
	'exp'        => '1.0',
	'database'   => undef,
	'scores'     => 50,
	'alignments' => 50,
);
GetOptions(

	# Tool specific options
	"program|p=s"    => \$tool_params{'program'},      # blastp, blastn, blastx, etc.
	"database|D=s"   => \$params{'database'},          # Database(s) to search
	"matrix|m=s"     => \$tool_params{'matrix'},       # Scoring martix to use
	"exp|E=f"        => \$tool_params{'exp'},          # E-value threshold
	"filter|f"       => \$tool_params{'filter'},       # Low complexity filter
	"align|A=i"      => \$tool_params{'align'},        # Pairwise alignment format
	"scores|s=i"     => \$tool_params{'scores'},       # Number of scores
	"alignments|n=i" => \$tool_params{'alignments'},   # Number of alignments
	"dropoff|d=i"    => \$tool_params{'dropoff'},      # Dropoff score
	"match_scores=s" => \$tool_params{'match_scores'}, # Match/missmatch scores
	"match|u=i"      => \$params{'match'},             # Match score
	"mismatch|v=i"   => \$params{'mismatch'},          # Mismatch score
	"gapopen|o=i"    => \$tool_params{'gapopen'},      # Open gap penalty
	"gapext|x=i"     => \$tool_params{'gapext'},       # Gap extension penality
	"gapalign|g"     => \$tool_params{'gapalign'},     # Optimise gap alignments
	"stype=s"        => \$tool_params{'stype'},        # Sequence type 'protein' or 'dna'
	"seqrange=s"     => \$tool_params{'seqrange'},     # Query subsequence to use
	"sequence=s"     => \$params{'sequence'},          # Query sequence file or DB:ID

	# Generic options
	'email=s'       => \$params{'email'},          # User e-mail address
	'title=s'       => \$params{'title'},          # Job title
	'outfile=s'     => \$params{'outfile'},        # Output file name
	'outformat=s'   => \$params{'outformat'},      # Output file type
	'jobid=s'       => \$params{'jobid'},          # JobId
	'help|h'        => \$params{'help'},           # Usage help
	'async'         => \$params{'async'},          # Asynchronous submission
	'polljob'       => \$params{'polljob'},        # Get results
	'resultTypes'   => \$params{'resultTypes'},    # Get result types
	'status'        => \$params{'status'},         # Get status
	'params'        => \$params{'params'},         # List input parameters
	'paramDetail=s' => \$params{'paramDetail'},    # Get details for parameter
	'quiet'         => \$params{'quiet'},          # Decrease output level
	'verbose'       => \$params{'verbose'},        # Increase output level
	'debugLevel=i'  => \$params{'debugLevel'},     # Debug output level
);
if ( $params{'verbose'} ) { $outputLevel++ }
if ( $params{'$quiet'} )  { $outputLevel-- }

# Get the script filename for use in usage messages
my $scriptName = basename( $0, () );

# Print usage and exit if requested
if ( $params{'help'} || $numOpts == 0 ) {
	&usage();
	exit(0);
}

if (
	!(
		   $params{'polljob'}
		|| $params{'resultTypes'}
		|| $params{'status'}
		|| $params{'params'}
		|| $params{'paramDetail'}
	)
	&& !( defined( $ARGV[0] ) || defined( $params{'sequence'} ) )
  )
{

	# Bad argument combination, so print error message and usage
	print STDERR 'Error: bad option combination', "\n";
	&usage();
	exit(1);
}

# Get parameters list
elsif ( $params{'params'} ) {
	&print_tool_params();
}

# Get parameter details
elsif ( $params{'paramDetail'} ) {
	&print_param_details( $params{'paramDetail'} );
}

# Job status
elsif ( $params{'status'} && defined( $params{'jobid'} ) ) {
	&print_job_status( $params{'jobid'} );
}

# Result types
elsif ( $params{'resultTypes'} && defined( $params{'jobid'} ) ) {
	&print_result_types( $params{'jobid'} );
}

# Poll job and get results
elsif ( $params{'polljob'} && defined( $params{'jobid'} ) ) {
	&get_results( $params{'jobid'} );
}

# Submit a job
else {
	&submit_job();
}

### Wrappers for REST resources ###

# Perform a REST request
#   my $response_str = &rest_request($url);
sub rest_request($) {
	print_debug_message( 'rest_request', 'Begin', 11 );
	my $requestUrl = shift;
	print_debug_message( 'rest_request', 'URL: ' . $requestUrl, 11 );
	# Create a user agent
	my $ua = LWP::UserAgent->new();
	$ua->env_proxy;
	# Perform the request
	my $response = $ua->get($requestUrl);
	print_debug_message( 'rest_request', 'HTTP status: ' . $response->code, 11 );
	# Check for HTTP error codes
	if($response->is_error) {
    	die 'http status: ' . $response->code . ' ' . $response->message;
	}
	print_debug_message( 'rest_request', 'End', 11 );
	# Return the response data
	return $response->content();
}

# Get list of tool parameters
#   my (@param_list) = &rest_get_parameters();
sub rest_get_parameters() {
	print_debug_message( 'rest_get_parameters', 'Begin', 1 );
	my $url = $baseUrl . '/parameters/';
	my $param_list_xml_str = rest_request($url);
	my $param_list_xml = XMLin($param_list_xml_str);
	my (@param_list) = @{$param_list_xml->{'id'}};
	print_debug_message( 'rest_get_parameters', 'End', 1 );
	return(@param_list);
}

# Get details of a tool parameter
#   my $paramDetail = &rest_get_parameter_details($param_name);
sub rest_get_parameter_details($) {
	print_debug_message( 'rest_get_parameter_details', 'Begin', 1 );
	my $parameterId = shift;
	print_debug_message( 'rest_get_parameter_details',
		'parameterId: ' . $parameterId, 1 );
	my $url = $baseUrl . '/parameterdetails/' . $parameterId;
	my $param_detail_xml_str = rest_request($url);
	my $param_detail_xml = XMLin($param_detail_xml_str);
	print_debug_message( 'rest_get_parameter_details', 'End', 1 );
	return($param_detail_xml);
}

# Submit a job
#   my $job_id = &rest_run($email, $title, \%params );
sub rest_run($$$) {
	print_debug_message( 'rest_run', 'Begin', 1 );
	my $email  = shift;
	my $title  = shift;
	my $params = shift;
	print_debug_message( 'rest_run', 'email: ' . $email, 1 );
	if ( defined($title) ) {
		print_debug_message( 'rest_run', 'title: ' . $title, 1 );
	}
	print_debug_message( 'rest_run', 'params: ' . Dumper($params), 1 );
	# User agent to perform http requests
	my $ua = LWP::UserAgent->new();
	$ua->env_proxy;
	# Clean up parameters
	my (%tmp_params) = %{$params};
	$tmp_params{'email'} = $email;
	$tmp_params{'title'} = $title;
	foreach my $param_name (keys(%tmp_params)) {
		if(!defined($tmp_params{$param_name})) {
			delete $tmp_params{$param_name};
		}
	}
	# Submit the job as a POST
	my $url = $baseUrl . '/run';
	my $response = $ua->post($url, \%tmp_params);
	print_debug_message( 'rest_run', 'HTTP status: ' . $response->code, 11 );
	print_debug_message( 'rest_run', 'request: ' . $response->request()->content(), 11 );
	# Check for HTTP error codes
	if($response->is_error) {
    	die 'http status: ' . $response->code . ' ' . $response->message;
	}
	# The job id is returned
	my $job_id = $response->content();
	print_debug_message( 'rest_run', 'End', 1 );
	return $job_id;
}

# Check the status of a job.
#   my $status = &rest_get_status($job_id);
sub rest_get_status($) {
	print_debug_message( 'rest_get_status', 'Begin', 1 );
	my $job_id = shift;
	print_debug_message( 'rest_get_status', 'jobid: ' . $job_id, 2 );
	my $status_str = 'UNKNOWN';
	my $url = $baseUrl . '/status/' . $job_id;
	$status_str = &rest_request($url);
	print_debug_message( 'rest_get_status', 'status_str: ' . $status_str, 2 );
	print_debug_message( 'rest_get_status', 'End', 1 );
	return $status_str;
}

# Get list of result types for finished job
#   my (@resultTypes) = &rest_get_result_types($job_id);
sub rest_get_result_types($) {
	print_debug_message( 'rest_get_result_types', 'Begin', 1 );
	my $job_id = shift;
	print_debug_message( 'rest_get_result_types', 'jobid: ' . $job_id, 2 );
	my (@resultTypes);
	my $url = $baseUrl . '/resulttypes/' . $job_id;
	my $result_type_list_xml_str = &rest_request($url);
	my $result_type_list_xml = XMLin($result_type_list_xml_str);
	(@resultTypes) = @{$result_type_list_xml->{'type'}};
	print_debug_message( 'rest_get_result_types',
		scalar(@resultTypes) . ' result types', 2 );
	print_debug_message( 'rest_get_result_types', 'End', 1 );
	return (@resultTypes);
}

# Get result data of a specified type for a finished job
#   my $result = rest_get_raw_result_output($job_id, $type);
sub rest_get_raw_result_output($$) {
	print_debug_message( 'rest_get_raw_result_output', 'Begin', 1 );
	my $job_id = shift;
	my $type  = shift;
	print_debug_message( 'rest_get_raw_result_output', 'jobid: ' . $job_id, 1 );
	print_debug_message( 'rest_get_raw_result_output', 'type: ' . $type,   1 );
	my $url = $baseUrl . '/result/' . $job_id . '/' . $type;
	my $result = &rest_request($url);
	print_debug_message( 'rest_get_raw_result_output',
		length($result) . ' characters', 1 );
	print_debug_message( 'rest_get_raw_result_output', 'End', 1 );
	return $result;
}

###  ###

# Print debug message
sub print_debug_message($$$) {
	my $function_name = shift;
	my $message       = shift;
	my $level         = shift;
	if ( $level <= $params{'debugLevel'} ) {
		print STDERR '[', $function_name, '()] ', $message, "\n";
	}
}

# Print list of tool parameters
sub print_tool_params() {
	print_debug_message( 'print_tool_params', 'Begin', 1 );
	my (@param_list) = &rest_get_parameters();
	foreach my $param (sort(@param_list)) {
		print $param, "\n";
	}
	print_debug_message( 'print_tool_params', 'End', 1 );
}

# Print details of a tool parameter
sub print_param_details($) {
	print_debug_message( 'print_param_details', 'Begin', 1 );
	my $paramName = shift;
	print_debug_message( 'print_param_details', 'paramName: ' . $paramName, 2 );
	my $paramDetail = &rest_get_parameter_details($paramName );
	print $paramDetail->{'name'}, "\t", $paramDetail->{'type'}, "\n";
	print $paramDetail->{'description'}, "\n";
	foreach my $value (@{$paramDetail->{'values'}->{'value'}}) {
		print $value->{'value'};
		if($value->{'defaultValue'} eq 'true') {
			print "\t", 'default';
		}
		print "\n";
		print "\t", $value->{'label'}, "\n";
	}
	print_debug_message( 'print_param_details', 'End', 1 );
}

# Print status of a job
sub print_job_status($) {
	print_debug_message( 'print_job_status', 'Begin', 1 );
	my $jobid = shift;
	print_debug_message( 'print_job_status', 'jobid: ' . $jobid, 1 );
	if ( $outputLevel > 0 ) {
		print STDERR 'Getting status for job ', $jobid, "\n";
	}
	my $result = &rest_get_status($jobid);
	print "$result\n";
	if ( $result eq 'FINISHED' && $outputLevel > 0 ) {
		print STDERR "To get results: $scriptName --polljob --jobid " . $jobid
		  . "\n";
	}
	print_debug_message( 'print_job_status', 'End', 1 );
}

# Print available result types for a job
sub print_result_types($) {
	print_debug_message( 'result_types', 'Begin', 1 );
	my $jobid = shift;
	print_debug_message( 'result_types', 'jobid: ' . $jobid, 1 );
	if ( $outputLevel > 0 ) {
		print STDERR 'Getting result types for job ', $jobid, "\n";
	}
	my $status = &rest_get_status($jobid);
	if ( $status eq 'PENDING' || $status eq 'RUNNING' ) {
		print STDERR 'Error: Job status is ', $status,
		  '. To get result types the job must be finished.', "\n";
	}
	else {
		my (@resultTypes) = &rest_get_result_types($jobid);
		if ( $outputLevel > 0 ) {
			print STDOUT 'Available result types:', "\n";
		}
		foreach my $resultType (@resultTypes) {
			print STDOUT $resultType->{'identifier'}, "\n";
			if(defined($resultType->{'label'})) {
				print STDOUT "\t", $resultType->{'label'},       "\n";
			}
			if(defined($resultType->{'description'})) {
				print STDOUT "\t", $resultType->{'description'}, "\n";
			}
			if(defined($resultType->{'mediaType'})) {
				print STDOUT "\t", $resultType->{'mediaType'},   "\n";
			}
			if(defined($resultType->{'fileSuffix'})) {
				print STDOUT "\t", $resultType->{'fileSuffix'},  "\n";
			}
		}
		if ( $status eq 'FINISHED' && $outputLevel > 0 ) {
			print STDERR "\n", 'To get results:', "\n",
			  "  $scriptName --polljob --jobid " . $params{'jobid'} . "\n",
			  "  $scriptName --polljob --outformat <type> --jobid "
			  . $params{'jobid'} . "\n";
		}
	}
	print_debug_message( 'result_types', 'End', 1 );
}

# Submit a job
sub submit_job() {
	print_debug_message( 'submit_job', 'Begin', 1 );

	# Load the sequence data
	&load_data();

	# Load parameters
	&load_params();

	# Submit the job
	my $jobid = &rest_run( $params{'email'}, $params{'title'}, \%tool_params );

	# Simulate sync/async mode
	if ( defined( $params{'async'} ) ) {
		print STDOUT $jobid, "\n";
		if ( $outputLevel > 0 ) {
			print STDERR
			  "To check status: $scriptName --status --jobid $jobid\n";
		}
	}
	else {
		if ( $outputLevel > 0 ) {
			print STDERR "JobId: $jobid\n";
		}
		sleep 1;
		&get_results($jobid);
	}
	print_debug_message( 'submit_job', 'End', 1 );
}

# Load sequence data
sub load_data() {
	print_debug_message( 'load_data', 'Begin', 1 );

	# Query sequence
	if ( defined( $ARGV[0] ) ) {    # Bare option
		if ( -f $ARGV[0] || $ARGV[0] eq '-' ) {    # File
			$tool_params{'sequence'} = &read_file( $ARGV[0] );
		}
		else {                                     # DB:ID or sequence
			$tool_params{'sequence'} = $ARGV[0];
		}
	}
	if ( $params{'sequence'} ) {                   # Via --sequence
		if ( -f $params{'sequence'} || $params{'sequence'} eq '-' ) {    # File
			$tool_params{'sequence'} = &read_file( $params{'sequence'} );
		}
		else {    # DB:ID or sequence
			$tool_params{'sequence'} = $params{'sequence'};
		}
	}
	print_debug_message( 'load_data', 'End', 1 );
}

# Load job parameters
sub load_params() {
	print_debug_message( 'load_params', 'Begin', 1 );

	# Database(s) to search
	my (@dbList) = split /[ ,]/, $params{'database'};
	$tool_params{'database'} = \@dbList;

	# Match/missmatch
	if ( $params{'match'} && $params{'missmatch'} ) {
		$tool_params{'match_scores'} =
		  $params{'match'} . ',' . $params{'missmatch'};
	}
	print_debug_message( 'load_params', 'End', 1 );
}

# Client-side job polling
sub client_poll($) {
	print_debug_message( 'client_poll', 'Begin', 1 );
	my $jobid  = shift;
	my $result = 'PENDING';

	# Check status and wait if not finished
	#print STDERR "Checking status: $jobid\n";
	while ( $result eq 'RUNNING' || $result eq 'PENDING' ) {
		$result = rest_get_status($jobid);
		if ( $outputLevel > 0 ) {
			print STDERR "$result\n";
		}
		if ( $result eq 'RUNNING' || $result eq 'PENDING' ) {

			# Wait before polling again.
			sleep $checkInterval;
		}
	}
	print_debug_message( 'client_poll', 'End', 1 );
}

# Get the results for a jobid
sub get_results($) {
	print_debug_message( 'get_results', 'Begin', 1 );
	my $jobid = shift;
	print_debug_message( 'get_results', 'jobid: ' . $jobid, 1 );

	# Verbose
	if ( $outputLevel > 1 ) {
		print 'Getting results for job ', $jobid, "\n";
	}

	# Check status, and wait if not finished
	client_poll($jobid);

	# Use JobId if output file name is not defined
	unless ( defined( $params{'outfile'} ) ) {
		$params{'outfile'} = $jobid;
	}

	# Get list of data types
	my (@resultTypes) = rest_get_result_types($jobid);

	# Get the data and write it to a file
	if ( defined( $params{'outformat'} ) ) {    # Specified data type
		my $selResultType;
		foreach my $resultType (@resultTypes) {
			if ( $resultType->{'identifier'} eq $params{'outformat'} ) {
				$selResultType = $resultType;
			}
		}
		if ( defined($selResultType) ) {
			my $result =
			  rest_get_raw_result_output( $jobid,
				$selResultType->{'identifier'} );
			if ( $params{'outfile'} eq '-' ) {
				write_file( $params{'outfile'}, $result );
			}
			else {
				write_file(
					$params{'outfile'} . '.'
					  . $selResultType->{'identifier'} . '.'
					  . $selResultType->{'fileSuffix'},
					$result
				);
			}
		}
		else {
			die 'Error: unknown result format "' . $params{'outformat'} . '"';
		}
	}
	else {    # Data types available
		      # Write a file for each output type
		for my $resultType (@resultTypes) {
			if ( $outputLevel > 1 ) {
				print STDERR 'Getting ', $resultType->{'identifier'}, "\n";
			}
			my $result =
			  rest_get_raw_result_output( $jobid, $resultType->{'identifier'} );
			if ( $params{'outfile'} eq '-' ) {
				write_file( $params{'outfile'}, $result );
			}
			else {
				write_file(
					$params{'outfile'} . '.'
					  . $resultType->{'identifier'} . '.'
					  . $resultType->{'fileSuffix'},
					$result
				);
			}
		}
	}
	print_debug_message( 'get_results', 'End', 1 );
}

# Read a file
sub read_file($) {
	print_debug_message( 'read_file', 'Begin', 1 );
	my $filename = shift;
	my ( $content, $buffer );
	if ( $filename eq '-' ) {
		while ( sysread( STDIN, $buffer, 1024 ) ) {
			$content .= $buffer;
		}
	}
	else {    # File
		open( FILE, $filename )
		  or die "Error: unable to open input file $filename ($!)";
		while ( sysread( FILE, $buffer, 1024 ) ) {
			$content .= $buffer;
		}
		close(FILE);
	}
	print_debug_message( 'read_file', 'End', 1 );
	return $content;
}

# Write a result file
sub write_file($$) {
	print_debug_message( 'write_file', 'Begin', 1 );
	my ( $filename, $data ) = @_;
	if ( $outputLevel > 0 ) {
		print STDERR 'Creating result file: ' . $filename . "\n";
	}
	if ( $filename eq '-' ) {
		print STDOUT $data;
	}
	else {
		open( FILE, ">$filename" )
		  or die "Error: unable to open output file $filename ($!)";
		syswrite( FILE, $data );
		close(FILE);
	}
	print_debug_message( 'write_file', 'End', 1 );
}

# Print program usage
sub usage {
	print STDERR <<EOF
NCBI BLAST
==========
   
Rapid sequence database search programs utilizing the BLAST algorithm
    
For more detailed help information refer to 
http://www.ebi.ac.uk/Tools/blastall/help.html

[Required]

  -p, --program	    : str  : BLAST program to use, see --paramDetail program
  -D, --database    : str  : database(s) to search, space separated. See
                             --paramDetail database
      --stype       : str  : query sequence type, see --paramDetail stype
  seqFile           : file : query sequence ("-" for STDIN)

[Optional]

  -m, --matrix      : str  : scoring matrix, see --paramDetail matrix
  -e, --exp         : real : 0<E<= 1000. Statistical significance threshold 
                             for reporting database sequence matches.
  -f, --filter	    :      : filter the query sequence for low complexity 
                             regions, see --paramDetail filter
  -A, --align	    : int  : pairwise alignment format, see --paramDetail align
  -s, --scores	    : int  : number of scores to be reported
  -n, --alignments  : int  : number of alignments to report
  -u, --match       : int  : Match score (BLASTN only)
  -v, --mismatch    : int  : Mismatch score (BLASTN only)
  -o, --gapopen	    : int  : Gap open penalty
  -x, --gapext      : int  : Gap extension penalty
  -d, --dropoff	    : int  : Drop-off
  -g, --gapalign    :      : Optimise gapped alignments
      --seqrange    : str  : region within input to use as query

[General]

  -h, --help        :      : prints this help text
      --async       :      : forces to make an asynchronous query
      --email	    : str  : e-mail address
      --title       : str  : title for job
      --status      :      : get job status
      --resultTypes :      : get available result types for job
      --polljob     :      : poll for the status of a job
      --jobid       : str  : jobid that was returned when an asynchronous job 
                             was submitted.
      --outfile     : str  : file name for results (default is jobid;
                             "-" for STDOUT)
      --outformat   : str  : result format to retrieve
      --params      :      : list input parameters
      --paramDetail : str  : display details for input parameter
      --quiet       :      : decrease output
      --verbose     :      : increase output
      --trace	    :      : show SOAP messages being interchanged 
   
Synchronous job:

  The results/errors are returned as soon as the job is finished.
  Usage: $scriptName --email <your\@email> [options...] seqFile
  Returns: results as an attachment

Asynchronous job:

  Use this if you want to retrieve the results at a later time. The results 
  are stored for up to 24 hours. 	
  Usage: $scriptName --async --email <your\@email> [options...] seqFile
  Returns: jobid

  Use the jobid to query for the status of the job. If the job is finished, 
  it also returns the results/errors.
  Usage: $scriptName --polljob --jobid <jobId> [--outfile string]
  Returns: string indicating the status of the job and if applicable, results 
  as an attachment.

Further information:

  http://www.ebi.ac.uk/Tools/ncbiblast/
  http://www.ebi.ac.uk/Tools/webservices/clients/ncbiblast
  http://www.ebi.ac.uk/Tools/webservices/services/ncbiblast
  http://www.ebi.ac.uk/Tools/webservices/tutorials/perl
EOF
}