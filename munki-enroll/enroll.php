<?php

require_once( 'cfpropertylist-1.1.2/CFPropertyList.php' );

// Get the varibles passed by the enroll script
$identifier = $_POST["identifier"];
$hostname   = $_POST["hostname"];

// Split the manifest path up to determine directory structure
$directories		= explode( "/", $identifier, -1 ); 
$total				= count( $directories );
$n					= 0;
$identifier_path	= "";
while ( $n < $total )
    {
        $identifier_path .= $directories[$n] . '/';
        $n++;
    }

echo "\n\tMUNKI-ENROLLER. Checking for existing manifests.\n\n";

// Check if manifest already exists for this machine
if ( file_exists( '../manifests/client-' . $hostname ) )
    {
        echo "\tComputer manifest already exists.\n";
        echo "\tPrevious settings will still apply to this computer.\n\n";
        echo "\tYour manifest is: client-" . $hostname . "\n\n";
    }
else
    {
        echo "\tComputer manifest does not exist. Will create.\n\n";
        
        $plist = new CFPropertyList();
        $plist->add( $dict = new CFDictionary() );
        
        // Add manifest to production catalog by default
        $dict->add( 'catalogs', $array = new CFArray() );
        $array->add( new CFString( 'standard' ) );
        
        // Add parent manifest to included_manifests to achieve waterfall effect
        $dict->add( 'included_manifests', $array = new CFArray() );
        $array->add( new CFString( $identifier ) );
        
        // Save the newly created plist
        $plist->saveXML( '../manifests/client-' . $hostname );
        chmod( '../manifests/client-' . $hostname, 0777 );
        echo "\tNew manifest created: client-" . $hostname . "\n";
        echo "\tIncluded Manifest: " . $identifier . "\n";
        
    }

?>