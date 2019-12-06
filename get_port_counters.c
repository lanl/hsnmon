/*
 * © (or copyright) 2019. Triad National Security, LLC. All rights reserved.
 * This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
 * National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
 * Department of Energy/National Nuclear Security Administration. All rights in the program are
 * reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
 * Security Administration. The Government is granted for itself and others acting on its behalf a
 * nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
 * derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
 * others to do so.
 */


/*
 * Service: HSNMon
 * Source File: get_port_counters.c
 * Usage: Gets HSN counters and timestamp fast and accurately from the PA/SA
 * Called From: hsnmon.pl
 * Note: This code utilizes the Intel opamgt API
 * For reference, please observe the latest Intel docs, currently:
 * https://www.intel.com/content/dam/support/us/en/documents/network-and-i-o/fabric-products/Intel_OPA_MGT_API_PG_J68876_v4_0.pdf
 * additionally, many of the data structures accessed via the API are not undocumented
 * the source code of opa-ff is the only documentation that I am aware of:
 * https://github.com/intel/opa-ff
 */

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <unistd.h>
#include <signal.h>

#include <opamgt/opamgt.h>
#include <opamgt/opamgt_pa.h>
#include <opamgt/opamgt_sa.h>

#define SLEEP_TIME 1

#define FLITS_PER_MB ((uint64)1000*(uint64)1000/(uint64)8)

struct link {
	unsigned int from_lid;
	int from_port;
	unsigned int to_lid;
	int to_port;
};

static const char hdr_line[] = "Node;Port;Image_Start;Image_Duration;Image_ID;numNoRespPorts;XmitDataMB;RcvDataMB;XmitWait;CongDiscards;XmitDiscards";
static const char fmt_line[] = "%s;%d;%s;%u.%03u;0x%"PRIx64";%u;%"PRIu64";%"PRIu64";%"PRIu64";%"PRIu64";%"PRIu64;

void sig_quit(int sig);
int get_port_info(struct omgt_port * m_port);
int get_link(struct omgt_port * m_port, STL_LID lid, struct link *l);
int get_link2(STL_LINK_RECORD * link_records, int *num_records, STL_LID lid ,struct link *l);
int get_links(struct omgt_port * m_port, STL_LINK_RECORD ** link_records, int * num_records);
char * get_counters(struct omgt_port * m_port, STL_LID lid, int port, uint8 * NodeDesc,
	STL_PA_IMAGE_ID_DATA image_ID, STL_PA_IMAGE_INFO_DATA image_info);

void sig_quit(int sig) { fprintf(stderr, "Core dump, fabric error [sig %d]\n", sig);_exit(1); }



unsigned int sleep_time[1];
int main(int argc, char *argv[])
{

	// for polling the PA, get a sleep time or default to 1 second
	if(argc == 1) {
		*sleep_time = SLEEP_TIME;
	} else if (argc > 2){
		fprintf(stderr, "ERROR: Only one argument allowed\n");
		_exit(1);
	} else {
		char * err;
		const long zero = 0;
		if(strtol(argv[1],&err,10) < zero){
			fprintf(stderr, "ERROR: Failed to parse [%s] as a number\n",argv[1]);
			_exit(1);
		}
		*sleep_time = (unsigned int) strtol(argv[1],&err,10);
		if(*err){
			fprintf(stderr, "ERROR: Failed to parse [%s] as a number\n",argv[1]);
			_exit(1);
		}
	}
	fprintf(stderr, "Passed sleep time of %u\n", *sleep_time);

	// if fabric falls over, the opamgt library throws a segfault
	// we just want to exit, no segfault
	signal(SIGSEGV, sig_quit);

	// create a session
	int exitcode = 0;
	OMGT_STATUS_T status;
	struct omgt_port * m_port = NULL;

	status = omgt_open_port_by_num(&m_port, 1 /* hfi */, 1 /* port */, NULL);
	if(OMGT_STATUS_SUCCESS != status) {
		fprintf(stderr, "Failed to open port or initialize PA connection\n");
		exitcode=1;
		goto fail1;
	}

	// forever get ports
	while(1){
		exitcode = get_port_info(m_port);
		if(exitcode){
			fprintf(stderr, "Failed to get port info\n");
		}
	}

	// close our session
	omgt_close_port(m_port);
	fail1:
	return exitcode;
}


/**************************************************************
 * This function queries the mgmt port for the link of a lid
 * and stores the send/rcv port/lid in the given link struct.
 **************************************************************/
int get_link(struct omgt_port * m_port, STL_LID lid, struct link *l){

	void *link_records = NULL;
	omgt_sa_selector_t selector;
	OMGT_STATUS_T status = OMGT_STATUS_SUCCESS;
	int num_records=0;
	int rc=0;

	selector.InputType = InputTypeLid;
	selector.InputValue.LinkRecord.Lid = lid;

	// query the port
	status = omgt_sa_get_link_records(m_port, &selector, &num_records, (STL_LINK_RECORD **)&link_records);
	if (status != OMGT_STATUS_SUCCESS){
        	fprintf(stderr, "Failed to get link records\n");
		rc = 1;
	} else {

		// store result in link struct
		// this function is only used on nodes, so only query for one OPA link per node
		// obviously this will break on nodes with two links
		STL_LINK_RECORD *link_record = &((STL_LINK_RECORD *)link_records)[0];
		l->from_lid = (unsigned int) link_record->RID.FromLID;
		l->from_port = (unsigned int) link_record->RID.FromPort;
		l->to_lid = (unsigned int) link_record->ToLID;
		l->to_port = (unsigned int) link_record->ToPort;
	}

	// free our result buffer...
	if (link_records) omgt_sa_free_records(link_records);

	return rc;
}


/******************************************************************
 * This function queries the mgmt port for all links on the fabric
 * and stores the links in link_records.
 *****************************************************************/
int get_links(struct omgt_port * m_port, STL_LINK_RECORD ** link_records, int * num_records){

	OMGT_STATUS_T status = OMGT_STATUS_SUCCESS;
	omgt_sa_selector_t selector;
	int rc=0;

	// unfiltered results
	selector.InputType = InputTypeNoInput;

	// query for all the linke records
	status = omgt_sa_get_link_records(m_port, &selector, num_records, link_records);
	if (status != OMGT_STATUS_SUCCESS){
        fprintf(stderr, "Failed to get link records\n");
		rc = 1;
	}
	return rc;
}


/*******************************************************************
 * This function takes in a list of all links on a fabric and finds
 * the lid requested and stores that lid's link info in the link struct
 * for a 1500 node system, this is much faster than get_link(), however
 * an even bigger system *might* benefig from using get_link()
 *******************************************************************/
int get_link2(STL_LINK_RECORD * link_records, int *num_records, STL_LID lid ,struct link *l){
	int i;
	int rc = 1;

	// search the STL_LINK_RECORDs for the matching lid
	// this function is only used on single port nodes, so no need to check for multiple ports
	for(i=0; i<*num_records; i++){
		if(link_records[i].RID.FromLID == lid){
			l->from_lid = (unsigned int) link_records[i].RID.FromLID;
			l->from_port = (unsigned int) link_records[i].RID.FromPort;
			l->to_lid = (unsigned int) link_records[i].ToLID;
			l->to_port = (unsigned int) link_records[i].ToPort;
			rc = 0;
			break;
		}
	}
	return rc;
}


/*****************************************************
 * query the pa for Xmit/Rcv counters by lid/port_num *
 ******************************************************/
char * get_counters(struct omgt_port * m_port,
	STL_LID lid,
	int port,
	uint8 * NodeDesc,
	STL_PA_IMAGE_ID_DATA image_ID,
	STL_PA_IMAGE_INFO_DATA image_info){

	STL_PORT_COUNTERS_DATA port_counters;

	// Request port statistics capture in image specified by
	// image_ID and store in port_counters
	if (omgt_pa_get_port_stats2(m_port,
		image_ID /*requested*/,
		lid /* node LID*/,
		port /* port number*/,
		&image_ID /*received*/,
		&port_counters,
		NULL /*no flags*/,
		0 /* totals */,
		1 /*running counters */)){

        fprintf(stderr, "Failed to get port counters\n");

		return NULL;
        }

	// get string size
	//const size_t one_character = 1;
	size_t buf_size = (size_t)(1 + snprintf(NULL, 0, fmt_line,
	NodeDesc,
	port,
	strtok(ctime((time_t *)&image_info.sweepStart), "\n"),
	image_info.sweepDuration/1000000,
	(image_info.sweepDuration % 1000000)/1000,
	image_info.imageId.imageNumber,
	image_info.numNoRespPorts,
	port_counters.portXmitData/FLITS_PER_MB,		// XmitDataMB
	port_counters.portRcvData/FLITS_PER_MB,			// RcvDataMB
	port_counters.portXmitWait,			        // XmitWait
	port_counters.swPortCongestion,				// CongDiscards
	port_counters.portXmitDiscards));			// XmitDiscards


	// create string
	char * msg = malloc(buf_size);
	if(!msg){
		fprintf(stderr, "Failed to allocate memory\n");
		exit(EXIT_FAILURE);
	}

	// insert values into string
	sprintf(msg, fmt_line,
	NodeDesc,
	port,
	strtok(ctime((time_t *)&image_info.sweepStart), "\n"),
	image_info.sweepDuration/1000000,
	(image_info.sweepDuration % 1000000)/1000,
	image_info.imageId.imageNumber,
	image_info.numNoRespPorts,
	port_counters.portXmitData/FLITS_PER_MB,		// XmitDataMB
	port_counters.portRcvData/FLITS_PER_MB,			// RcvDataMB
	port_counters.portXmitWait,				// XmitWait
	port_counters.swPortCongestion,				// CongDiscards
	port_counters.portXmitDiscards);			// XmitDiscards

	return msg;
}


/************************************************
 * query the sa for list of all nodes in fabric, *
 * then query pa for the most recent image and   *
 * use get_counters on each record returned      *
 *************************************************/
int get_port_info(struct omgt_port * m_port){

	OMGT_STATUS_T status = OMGT_STATUS_SUCCESS;
	int exitcode = 0;
	int i;
	int num_node_records;
	static STL_PA_IMAGE_INFO_DATA last_image_info;
	STL_NODE_RECORD * records;
	STL_NODE_RECORD * r;

	// specify how and what we want to query
	omgt_sa_selector_t selector;
	selector.InputType = InputTypeNoInput;

	//execute query synchronously
	status = omgt_sa_get_node_records(m_port, &selector, &num_node_records, &records);

	if (status != OMGT_STATUS_SUCCESS) {
		exitcode=1;
		fprintf(stderr, "failed to execute query. MadStatus=0x%x\n",
		omgt_get_sa_mad_status(m_port));
		goto free_records;
	}
	if (!num_node_records) {

		// we can check result count independent of result type
		fprintf(stderr, "No records found.\n");
		goto free_records;

	}

	// queries that take an STL_PA_IMADE_ID_DATA argument
	// can be passed this cleared image to request current data
	STL_PA_IMAGE_ID_DATA image_ID = {0};
	STL_PA_IMAGE_INFO_DATA image_info;


	// Request information about the image specified by image_ID
	// This returns meta information about PM sweeps such as start
	// and duration
	if (omgt_pa_get_image_info(m_port, image_ID, &image_info)){
		fprintf(stderr, "Failed to get PA image\n");
		exitcode = 1;
		goto free_records;
	}
	if(image_info.imageId.imageNumber == last_image_info.imageId.imageNumber){
		fprintf(stderr,
		"Duplicate image [0x%" PRIx64 "] skipping...\n",
		image_info.imageId.imageNumber);
		sleep(sleep_time[0]);
		exitcode = 0;
		goto free_records;
	}

	int num_records;
	char malloc_flag = 0;
	struct link link;
	STL_LINK_RECORD *link_records = NULL;

	// get an array that holds all the links
	get_links(m_port, &link_records, &num_records);

	// print a header that explains the csv fields
	printf("%s\n", hdr_line);

	// iterate each device in the fabric
	for (i = 0; i < (num_node_records); ++i) {

		r = &records[i];

		// query for the node's counters
		if(r->NodeInfo.NodeType != STL_NODE_SW)	{
			char * msg;
			msg = get_counters(
			m_port,
			r->RID.LID,
			1, /*port num*/
			r->NodeDesc.NodeString,
			image_ID,
			image_info);
			if(msg){
				printf("%s\n", msg);
				free(msg);
			}

			// query for the remote switch port/lid
			if(get_link2(link_records, &num_records, r->RID.LID, &link)){

				// try falling back to the slow way
				get_link(m_port, r->RID.LID, &link);
				fprintf(stderr, "Link not found\n");
				break;
			}

			// search for the Switch's NodeDesc
			int j;
			uint8 * switch_description = NULL;
			for (j = 0; j < (num_node_records); ++j) {

				// find the NodeDesc with the matching lid
				if(records[j].RID.LID == link.to_lid){
					switch_description = (records[j].NodeDesc.NodeString);
					break;
				}
			}
			// error handling
			if (!switch_description){
				switch_description = malloc(10);
				memcpy(switch_description, "not found", 10);
				malloc_flag = 1;
			}

			// query for the switch port's counters
			msg = get_counters(
				m_port,
				link.to_lid,
				link.to_port,
				switch_description,
				image_ID,
				image_info);
			if(msg){
				printf("%s\n", msg);
				free(msg);
			}
			if(malloc_flag){
				free(switch_description);
				switch_description = NULL;
				malloc_flag = 0;
			}
		}
	}

	// save so we can compare to avoid duplicates
	last_image_info = image_info;
	if (link_records) {
	    omgt_sa_free_records(link_records);
	}
	free_records:
		// free our result buffer...
		if (records) {
		    omgt_sa_free_records(records);
		}
	return exitcode;
}
