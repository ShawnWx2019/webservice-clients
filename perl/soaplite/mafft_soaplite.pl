#!/usr/bin/env perl

=head1 NAME

mafft_soaplite.pl

=head1 DESCRIPTION

MAFFT SOAP web service Perl client using L<SOAP::Lite>.

Tested with:

=over

=item *
L<SOAP::Lite> 0.60 and Perl 5.8.3

=item *
L<SOAP::Lite> 0.69 and Perl 5.8.8

=item *
L<SOAP::Lite> 0.71 and Perl 5.8.8

=item *
L<SOAP::Lite> 0.710.08 and Perl 5.10.0 (Ubuntu 9.04)

=back

For further information see:

=over

=item *
L<http://www.ebi.ac.uk/Tools/webservices/services/msa/mafft_soap>

=item *
L<http://www.ebi.ac.uk/Tools/webservices/tutorials/perl>

=back

=head1 VERSION

$Id$

=cut

# ======================================================================
# Enable Perl warnings
use strict;
use warnings;

# Load libraries
use SOAP::Lite;
use LWP::Simple;
use Getopt::Long qw(:config no_ignore_case bundling);
use File::Basename;
use MIME::Base64;
use Data::Dumper;

# WSDL URL for service
my $WSDL = 'http://www.ebi.ac.uk/Tools/services/soap/mafft?wsdl';

# Set interval for checking status
my $checkInterval = 3;

# Output level
my $outputLevel = 1;

# Process command-line options
my $numOpts = scalar(@ARGV);
my %params = ( 'debugLevel' => 0 );

# Default parameter values (should get these from the service)
my %tool_params = ();
GetOptions(

	# Tool specific options
    'format|f=s'    => \$tool_params{'format'},     # Alignment format
    'matrix|m=s'    => \$tool_params{'matrix'},     # Protein scoring matrix
    'gapopen|g=f'   => \$tool_params{'gapopen'},    # Gap creation penalty
    'gapext|x=f'    => \$tool_params{'gapext'},     # Gap extension penalty
    'order|r=s'     => \$tool_params{'order'},      # Order of sequences in alignment
    'nbtree=i'      => \$tool_params{'nbtree'},     # Tree Rebuilding Number
    'maxiterate=i'  => \$tool_params{'maxiterate'}, # Maximum iterations
    'ffts=s'        => \$tool_params{'ffts'},       # Perform FFTS
    'sequence=s'    => \$params{'sequence'},        # Input sequences/alignment

	# Compatability options (old command-line)
    'gepen=f'      => \$params{'gepen'},         # Gap extension penalty
    'retree=i'     => \$params{'retree'},        # Tree rebuilding number
    'pair=s'       => \$params{'pair'},          # FFTS
    'localpair'    => \$params{'localpair'},     # FFTS: Local pair
    'globalpair'   => \$params{'globalpair'},    # FFTS: Global pair
    'genafpair'    => \$params{'genafpair'},     # FFTS
    'reorder'      => \$params{'reorder'},       # Output order
    'clustalout'   => \$params{'clustalout'},    # ClustalW format output
	
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
	'trace'         => \$params{'trace'},          # SOAP message debug
	'endpoint=s'    => \$params{'endpoint'},       # SOAP service endpoint
	'namespace=s'   => \$params{'namespace'},      # SOAP service namespace
	'WSDL=s'        => \$WSDL,                     # SOAP service WSDL
);
if ( $params{'verbose'} ) { $outputLevel++ }
if ( $params{'$quiet'} )  { $outputLevel-- }

# Debug mode: SOAP::Lite version
&print_debug_message( 'MAIN', 'SOAP::Lite::VERSION: ' . $SOAP::Lite::VERSION,
	1 );

# Debug mode: print the input parameters
&print_debug_message( 'MAIN', "params:\n" . Dumper( \%params ),           11 );
&print_debug_message( 'MAIN', "tool_params:\n" . Dumper( \%tool_params ), 11 );

# Get the script filename for use in usage messages
my $scriptName = basename( $0, () );

# Print usage and exit if requested
if ( $params{'help'} || $numOpts == 0 ) {
	&usage();
	exit(0);
}

# If required enable SOAP message trace
if ( $params{'trace'} ) {
	print STDERR "Tracing active\n";
	SOAP::Lite->import( +trace => 'debug' );
}

# Debug mode: show the WSDL, service endpoint and namespace being used.
&print_debug_message( 'MAIN', 'WSDL: ' . $WSDL, 1 );

# For a document/literal service which has types with repeating elements
# namespace and endpoint need to be used instead of the WSDL. By default
# these are extracted from the WSDL.
my ( $serviceEndpoint, $serviceNamespace ) = &from_wsdl($WSDL);

# User specified endpoint and namespace
$serviceEndpoint  = $params{'endpoint'}  if ( $params{'endpoint'} );
$serviceNamespace = $params{'namespace'} if ( $params{'namespace'} );

# Debug mode: show the WSDL, service endpoint and namespace being used.
&print_debug_message( 'MAIN', 'endpoint: ' . $serviceEndpoint,   11 );
&print_debug_message( 'MAIN', 'namespace: ' . $serviceNamespace, 11 );

# Create the service interface, setting the fault handler to throw exceptions
my $soap = SOAP::Lite->proxy(
	$serviceEndpoint,
	timeout => 6000,    # HTTP connection timeout
	     #proxy => ['http' => 'http://your.proxy.server/'], # HTTP proxy
  )->uri($serviceNamespace)->on_fault(

	# Map SOAP faults to Perl exceptions (i.e. die).
	sub {
		my $soap = shift;
		my $res  = shift;
		if ( ref($res) eq '' ) {
			die($res);
		}
		else {
			die( $res->faultstring );
		}
		return new SOAP::SOM;
	}
  );

# Check that arguments include required parameters
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
	# Load the sequence data and submit.
	&submit_job( &load_data() );
}

=head1 FUNCTIONS

=cut

### Wrappers for SOAP operations ###

=head2 soap_get_parameters()

Get a list of tool parameter names.

  my (@param_name_list) = &soap_get_parameters();

=cut

sub soap_get_parameters {
	print_debug_message( 'soap_get_parameters', 'Begin', 1 );
	my $ret = $soap->getParameters(undef);
	print_debug_message( 'soap_get_parameters', 'End', 1 );
	return $ret->valueof('//parameters/id');
}

=head2 soap_get_parameter_details();

Get detailed information about a tool parameter. Includes a description 
suitable for use in user help, and details of valid values. 

  my $paramDetail = &soap_get_parameter_details($paramName);

=cut

sub soap_get_parameter_details {
	print_debug_message( 'soap_get_parameter_details', 'Begin', 1 );
	my $parameterId = shift;
	print_debug_message( 'soap_get_parameter_details',
		'parameterId: ' . $parameterId, 1 );
	my $ret = $soap->getParameterDetails(
		SOAP::Data->name( 'parameterId' => $parameterId )
		  ->attr( { 'xmlns' => '' } ) );
	my $paramDetail = $ret->valueof('//parameterDetails');
	my (@paramValueList) = $ret->valueof('//parameterDetails/values/value');
	$paramDetail->{'values'} = \@paramValueList;
	print_debug_message( 'soap_get_parameter_details', 'End', 1 );
	return $paramDetail;
}

=head2 soap_run()

Submit a job to the service.

  my $job_id = &soap_run($email, $title, \%params);

=cut

sub soap_run {
	print_debug_message( 'soap_run', 'Begin', 1 );
	my $email  = shift;
	my $title  = shift;
	my $params = shift;
	print_debug_message( 'soap_run', 'email: ' . $email, 1 );
	if ( defined($title) ) {
		print_debug_message( 'soap_run', 'title: ' . $title, 1 );
	}

	my (@paramsList) = ();
	foreach my $key ( keys(%$params) ) {
		if ( defined( $params->{$key} ) && $params->{$key} ne '' ) {
			push @paramsList,
			  SOAP::Data->name( $key => $params->{$key} )
			  ->attr( { 'xmlns' => '' } );
		}
	}
	my $ret = $soap->run(
		SOAP::Data->name( 'email' => $email )->attr( { 'xmlns' => '' } ),
		SOAP::Data->name( 'title' => $title )->attr( { 'xmlns' => '' } ),
		SOAP::Data->name( 'parameters' => \SOAP::Data->value(@paramsList) )
		  ->attr( { 'xmlns' => '' } )
	);
	print_debug_message( 'soap_run', 'End', 1 );
	return $ret->valueof('//jobId');
}

=head2 soap_get_status()

Get the status of a submitted job.

  my $status = &soap_get_status($job_id);

=cut

sub soap_get_status {
	print_debug_message( 'soap_get_status', 'Begin', 1 );
	my $jobid = shift;
	print_debug_message( 'soap_get_status', 'jobid: ' . $jobid, 2 );
	my $res = $soap->getStatus(
		SOAP::Data->name( 'jobId' => $jobid )->attr( { 'xmlns' => '' } ) );
	my $status_str = $res->valueof('//status');
	print_debug_message( 'soap_get_status', 'status_str: ' . $status_str, 2 );
	print_debug_message( 'soap_get_status', 'End', 1 );
	return $status_str;
}

=head2 soap_get_result_types()

Get list of available result types for a finished job.

  my (@resultTypes) = soap_get_result_types($job_id);

=cut

sub soap_get_result_types {
	print_debug_message( 'soap_get_result_types', 'Begin', 1 );
	my $jobid = shift;
	print_debug_message( 'soap_get_result_types', 'jobid: ' . $jobid, 2 );
	my $resultTypesXml = $soap->getResultTypes(
		SOAP::Data->name( 'jobId' => $jobid )->attr( { 'xmlns' => '' } ) );
	my (@resultTypes) = $resultTypesXml->valueof('//resultTypes/type');
	print_debug_message( 'soap_get_result_types',
		scalar(@resultTypes) . ' result types', 2 );
	print_debug_message( 'soap_get_result_types', 'End', 1 );
	return (@resultTypes);
}

=head2 soap_get_result()

Get result data of a specified type for a finished job.

  my $result = &soap_get_result($job_id, $result_type);

=cut

sub soap_get_result {
	print_debug_message( 'soap_get_result', 'Begin', 1 );
	my $jobid = shift;
	my $type  = shift;
	print_debug_message( 'soap_get_result', 'jobid: ' . $jobid, 1 );
	print_debug_message( 'soap_get_result', 'type: ' . $type,   1 );
	my $res = $soap->getResult(
		SOAP::Data->name( 'jobId' => $jobid )->attr( { 'xmlns' => '' } ),
		SOAP::Data->name( 'type'  => $type )->attr(  { 'xmlns' => '' } )
	);
	my $result = decode_base64( $res->valueof('//output') );
	print_debug_message( 'soap_get_result', length($result) . ' characters',
		1 );
	print_debug_message( 'soap_get_result', 'End', 1 );
	return $result;
}

### Service actions and utility functions ###

=head2 print_debug_message()

Print a debug message at the specified debug level.

  &print_debug_message($function_name, $message, $level);

=cut

sub print_debug_message {
	my $function_name = shift;
	my $message       = shift;
	my $level         = shift;
	if ( $level <= $params{'debugLevel'} ) {
		print STDERR '[', $function_name, '()] ', $message, "\n";
	}
}

=head2 from_wsdl()

Extract the service namespace and endpoint from the service WSDL document 
for use when creating the service interface.

This function assumes that the WSDL contains a single service using a single
namespace and endpoint.

The namespace and endpoint are required to create a service interface, using 
SOAP::Lite->proxy(), that supports repeating elements (maxOcurrs > 1) as used 
in many document/literal services. Using SOAP::Lite->service() with the WSDL
gives an interface where the data structures returned by the service are 
mapped into hash structures and repeated elements are collapsed to a single
instance.

Note: rpc/encoded services are handled  as expected by SOAP::Lite->service() 
since repeating data structures are encoded using arrays by the service.  

  my ($serviceEndpoint, $serviceNamespace) = &from_wsdl($WSDL);

=cut

sub from_wsdl {
	&print_debug_message( 'from_wsdl', 'Begin', 1 );
	my (@retVal) = ();
	my $wsdlStr = get($WSDL); # Get WSDL using LWP.
	# Extract service endpoint.
	if ( $wsdlStr =~ m/<(\w+:)?address\s+location=["']([^'"]+)['"]/ ) {
		&print_debug_message( 'from_wsdl', 'endpoint: ' . $2, 2 );
		push( @retVal, $2 );
	}
	# Extract namespace.
	if ( $wsdlStr =~
		m/<(\w+:)?definitions\s*[^>]*\s+targetNamespace=['"]([^"']+)["']/ )
	{
		&print_debug_message( 'from_wsdl', 'namespace: ' . $2, 2 );
		push( @retVal, $2 );
	}
	&print_debug_message( 'from_wsdl', 'End', 1 );
	return @retVal;
}

=head2 print_tool_params()

Print the list of tool parameter names.

  &print_tool_params();

=cut

sub print_tool_params {
	print_debug_message( 'print_tool_params', 'Begin', 1 );
	my (@paramList) = &soap_get_parameters();
	foreach my $param (@paramList) {
		print $param, "\n";
	}
	print_debug_message( 'print_tool_params', 'End', 1 );
}

=head2 print_param_details()

Print detail information about a tool parameter.

  &print_param_details($param_name);

=cut

sub print_param_details {
	print_debug_message( 'print_param_details', 'Begin', 1 );
	my $paramName = shift;
	print_debug_message( 'print_param_details', 'paramName: ' . $paramName, 2 );
	my $paramDetail = &soap_get_parameter_details($paramName);
	print $paramDetail->{'name'}, "\t", $paramDetail->{'type'}, "\n";
	print $paramDetail->{'description'}, "\n";
	foreach my $value ( @{ $paramDetail->{'values'} } ) {
		print $value->{'value'};
		if ( $value->{'defaultValue'} eq 'true' ) {
			print "\t", 'default';
		}
		print "\n";
		print "\t", $value->{'label'}, "\n";
	}
	print_debug_message( 'print_param_details', 'End', 1 );
}

=head2  print_job_status()

Print the status of a submitted job.

  &print_job_status($job_id);

=cut

sub print_job_status {
	print_debug_message( 'print_job_status', 'Begin', 1 );
	my $jobid = shift;
	print_debug_message( 'print_job_status', 'jobid: ' . $jobid, 1 );
	if ( $outputLevel > 0 ) {
		print STDERR 'Getting status for job ', $jobid, "\n";
	}
	my $status = &soap_get_status($jobid);
	print "$status\n";
	if ( $status eq 'FINISHED' && $outputLevel > 0 ) {
		print STDERR "To get available result types:\n",
		  "  $scriptName --resultTypes --jobid $jobid\n";
	}
	print_debug_message( 'print_job_status', 'End', 1 );
}

=head2 print_result_types()

Print available result types for a finished job.

  &print_result_types($job_id);

=cut

sub print_result_types {
	print_debug_message( 'print_result_types', 'Begin', 1 );
	my $jobid = shift;
	print_debug_message( 'print_result_types', 'jobid: ' . $jobid, 1 );
	if ( $outputLevel > 0 ) {
		print STDERR 'Getting result types for job ', $jobid, "\n";
	}
	my $status = &soap_get_status($jobid);
	if ( $status eq 'PENDING' || $status eq 'RUNNING' ) {
		print STDERR 'Error: Job status is ', $status,
		  '. To get result types the job must be finished.', "\n";
	}
	else {
		my (@resultTypes) = &soap_get_result_types($jobid);
		if ( $outputLevel > 0 ) {
			print STDOUT 'Available result types:', "\n";
		}
		foreach my $resultType (@resultTypes) {
			print STDOUT $resultType->{'identifier'}, "\n";
			if ( defined( $resultType->{'label'} ) ) {
				print STDOUT "\t", $resultType->{'label'}, "\n";
			}
			if ( defined( $resultType->{'description'} ) ) {
				print STDOUT "\t", $resultType->{'description'}, "\n";
			}
			if ( defined( $resultType->{'mediaType'} ) ) {
				print STDOUT "\t", $resultType->{'mediaType'}, "\n";
			}
			if ( defined( $resultType->{'fileSuffix'} ) ) {
				print STDOUT "\t", $resultType->{'fileSuffix'}, "\n";
			}
		}
		if ( $status eq 'FINISHED' && $outputLevel > 0 ) {
			print STDERR "\n", 'To get results:', "\n",
			  "  $scriptName --polljob --jobid " . $params{'jobid'} . "\n",
			  "  $scriptName --polljob --outformat <type> --jobid "
			  . $params{'jobid'} . "\n";
		}
	}
	print_debug_message( 'print_result_types', 'End', 1 );
}

=head2 submit_job()

Submit a job to the service.

  &submit_job($seq);

=cut

sub submit_job {
	print_debug_message( 'submit_job', 'Begin', 1 );

	# Set input sequence
	$tool_params{'sequence'} = shift;

	# Load parameters
	&load_params();

	# Submit the job
	my $jobid = &soap_run( $params{'email'}, $params{'title'}, \%tool_params );

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

=head2 load_data()

Load sequence data, from file or direct specification of input data with 
command-line option.

  my $data = load_data();

=cut

sub load_data {
	print_debug_message( 'load_data', 'Begin', 1 );
	my $retSeq;

	# Query sequence
	if ( defined( $ARGV[0] ) ) {    # Bare option
		if ( -f $ARGV[0] || $ARGV[0] eq '-' ) {    # File
			$retSeq = &read_file( $ARGV[0] );
		}
		else {                                     # DB:ID or sequence
			$retSeq = $ARGV[0];
		}
	}
	if ( $params{'sequence'} ) {                   # Via --sequence
		if ( -f $params{'sequence'} || $params{'sequence'} eq '-' ) {    # File
			$retSeq = &read_file( $params{'sequence'} );
		}
		else {    # DB:ID or sequence
			$retSeq = $params{'sequence'};
		}
	}
	print_debug_message( 'load_data', 'End', 1 );
	return $retSeq;
}

=head2 load_params()

Load job parameters into input structure.

Since most of the loading is done when processing the command-line options, 
this function only provides additional processing required from some options.

  &load_params();

=cut

sub load_params {
	print_debug_message( 'load_params', 'Begin', 1 );

	# Compatability parameters
	if(!$tool_params{'gapext'} && $params{'gepen'}) {
		$tool_params{'gapext'} = $params{'gepen'};
	}
	if(!$tool_params{'nbtree'} && $params{'retree'}) {
		$tool_params{'nbtree'} = $params{'retree'};
	}
	if(!$tool_params{'ffts'} && $params{'pair'}) {
		$tool_params{'ffts'} = $params{'pair'};
	}
	if(!$tool_params{'ffts'} && $params{'localpair'}) {
		$tool_params{'ffts'} = 'localpair';
	}
	if(!$tool_params{'ffts'} && $params{'genafpair'}) {
		$tool_params{'ffts'} = 'genafpair';
	}
	if(!$tool_params{'ffts'} && $params{'globalpair'}) {
		$tool_params{'ffts'} = 'globalpair';
	}
	if(!$tool_params{'order'} && $params{'reorder'}) {
		$tool_params{'order'} = 'aligned';
	}
	if(!$tool_params{'format'} && $params{'clustalout'}) {
		$tool_params{'format'} = 'clustalw';
	}
	
	print_debug_message( 'load_params',
		"tool_params:\n" . Dumper( \%tool_params ), 2 );
	print_debug_message( 'load_params', 'End', 1 );
}

=head2 client_poll()

Client-side job polling.

  my $status = &client_poll($job_id);

=cut

sub client_poll {
	print_debug_message( 'client_poll', 'Begin', 1 );
	my $jobid  = shift;
	my $status = 'PENDING';

# Check status and wait if not finished. Terminate if three attempts get "ERROR".
	my $errorCount = 0;
	while ($status eq 'RUNNING'
		|| $status eq 'PENDING'
		|| ( $status eq 'ERROR' && $errorCount < 2 ) )
	{
		$status = soap_get_status($jobid);
		print STDERR "$status\n" if ( $outputLevel > 0 );
		if ( $status eq 'ERROR' ) {
			$errorCount++;
		}
		elsif ( $errorCount > 0 ) {
			$errorCount--;
		}
		if (   $status eq 'RUNNING'
			|| $status eq 'PENDING'
			|| $status eq 'ERROR' )
		{

			# Wait before polling again.
			sleep $checkInterval;
		}
	}
	print_debug_message( 'client_poll', 'End', 1 );
	return $status;
}

=head2 get_results()

Get the results for a jobid.

  &get_results($job_id);

=cut

sub get_results {
	print_debug_message( 'get_results', 'Begin', 1 );
	my $jobid = shift;
	print_debug_message( 'get_results', 'jobid: ' . $jobid, 1 );

	# Verbose
	print 'Getting results for job ', $jobid, "\n" if ( $outputLevel > 1 );

	# Check status, and wait if not finished
	my $status = client_poll($jobid);

	# If job completed get results
	if ( $status eq 'FINISHED' ) {

		# Use JobId if output file name is not defined
		$params{'outfile'} = $jobid unless ( defined( $params{'outfile'} ) );

		# Get list of data types
		my (@resultTypes) = soap_get_result_types($jobid);

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
				  soap_get_result( $jobid, $selResultType->{'identifier'} );
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
				die 'Error: unknown result format "'
				  . $params{'outformat'} . '"';
			}
		}
		else {

			# Data types available
			# Write a file for each output type
			for my $resultType (@resultTypes) {
				print STDERR 'Getting ', $resultType->{'identifier'}, "\n"
				  if ( $outputLevel > 1 );
				my $result =
				  soap_get_result( $jobid, $resultType->{'identifier'} );
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
	}
	else {
		print STDERR "Job failed, unable to get results\n";
	}
	print_debug_message( 'get_results', 'End', 1 );
}

=head2 read_file()

Read all data from a file. The special filename '-' can be used to read from 
standard input.

  my $data = &read_file($filename);

=cut

sub read_file {
	print_debug_message( 'read_file', 'Begin', 1 );
	my $filename = shift;
	my ( $content, $buffer );
	if ( $filename eq '-' ) {
		while ( sysread( STDIN, $buffer, 1024 ) ) {
			$content .= $buffer;
		}
	}
	else {    # File
		open( my $FILE, '<', $filename )
		  or die "Error: unable to open input file $filename ($!)";
		while ( sysread( $FILE, $buffer, 1024 ) ) {
			$content .= $buffer;
		}
		close($FILE);
	}
	print_debug_message( 'read_file', 'End', 1 );
	return $content;
}

=head2 write_file()

Write data to a file. The special filename '-' can be used to write to 
standard output.

  &write_file($filename, $data);

=cut

sub write_file {
	print_debug_message( 'write_file', 'Begin', 1 );
	my ( $filename, $data ) = @_;
	if ( $outputLevel > 0 ) {
		print STDERR 'Creating result file: ' . $filename . "\n";
	}
	if ( $filename eq '-' ) {
		print STDOUT $data;
	}
	else {
		open( my $FILE, '>', $filename )
		  or die "Error: unable to open output file $filename ($!)";
		syswrite( $FILE, $data );
		close($FILE);
	}
	print_debug_message( 'write_file', 'End', 1 );
}

=head2 usage()

Print program usage.

  &usage();

=cut

sub usage {
	print STDERR <<EOF
MAFFT
=====

MAFFT (Multiple Alignment using Fast Fourier Transform) is a high speed 
multiple sequence alignment program.
    
[Required]

  seqFile            : file : sequences to align ("-" for STDIN)

[Optional]

  -f, --format       : str  : alignment format, see --paramDetail format
  -m, --matrix       : str  : scoring matrix, see --paramDetail matrix
  -g, --gapopen      : real : gap creation penalty
  -x, --gapext       : real : gap extension penalty
  -r, --order        : str  : order of sequences in alignment, 
                              see --paramDetail order
      --nbtree       : int  : tree rebuilding number
      --maxiterate   : int  : maximum number of iterations
      --ffts         : str  : perform FFTS, see --paramDetail ffts

[General]

  -h, --help         :      : prints this help text
      --async        :      : forces to make an asynchronous query
      --email        : str  : e-mail address
      --title        : str  : title for job
      --status       :      : get job status
      --resultTypes  :      : get available result types for job
      --polljob      :      : poll for the status of a job
      --jobid        : str  : jobid that was returned when an asynchronous job 
                              was submitted.
      --outfile      : str  : file name for results (default is jobid;
                              "-" for STDOUT)
      --outformat    : str  : result format to retrieve
      --params       :      : list input parameters
      --paramDetail  : str  : display details for input parameter
      --quiet        :      : decrease output
      --verbose      :      : increase output
      --trace        :      : show SOAP messages being interchanged 

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

  http://www.ebi.ac.uk/Tools/webservices/services/msa/mafft_soap
  http://www.ebi.ac.uk/Tools/webservices/tutorials/perl

Support/Feedback:

  http://www.ebi.ac.uk/support/
EOF
}

=head1 FEEDBACK/SUPPORT

Please contact us at L<http://www.ebi.ac.uk/support/> if you have any 
feedback, suggestions or issues with the service or this client.

=cut