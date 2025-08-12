
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <syslog.h>

int main(int argc, char * argv[]){
	openlog("writer", 0, LOG_USER);
	
	if (argc!=3){
		syslog(LOG_ERR, "Not enough/Too many args \n");
		closelog();
		printf("args %i", argc);
		return 1; 
	}
	
	char writefile[128];
	char writestr[256]; 
	strcpy(writefile, argv[1]);
	strcpy(writestr, argv[2]);
	FILE *file = fopen (writefile, "w");
	if (file == NULL){
		fprintf(stderr, "Error opening file %s: %s \n" , writefile, strerror(errno));
		syslog(LOG_ERR, "Error opening file %s: %s \n", writefile, strerror(errno));
		closelog();
		return 1;
		
	}
	else{
		syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);
		fwrite(writestr,1,strlen(writestr),file);
		fclose(file);
	}
	closelog();
	return 0;

}
