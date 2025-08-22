#include <OpenDirectory/OpenDirectory.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <username>\n", argv[0]);
        return 2;
    }

    char *username = argv[1];

    // Read password from stdin
    char password[1024];
    if (!fgets(password, sizeof(password), stdin)) {
        fprintf(stderr, "No password input\n");
        return 3;
    }

    // Strip trailing newline
    size_t len = strlen(password);
    if (len > 0 && password[len-1] == '\n') {
        password[len-1] = '\0';
    }

    ODSessionRef session = ODSessionCreate(NULL, NULL, NULL);
    if (!session) return 4;

    ODNodeRef node = ODNodeCreateWithNodeType(NULL, session,
                                              kODNodeTypeAuthentication, NULL);
    if (!node) {
        CFRelease(session);
        return 5;
    }

    CFStringRef cfUser = CFStringCreateWithCString(NULL, username, kCFStringEncodingUTF8);
    CFStringRef cfPass = CFStringCreateWithCString(NULL, password, kCFStringEncodingUTF8);

    ODRecordRef rec = ODNodeCopyRecord(node, kODRecordTypeUsers, cfUser, NULL, NULL);
    if (!rec) {
        CFRelease(cfUser);
        CFRelease(cfPass);
        CFRelease(node);
        CFRelease(session);
        return 1;  // treat missing record as "bad login"
    }

    OSStatus status = ODRecordVerifyPassword(rec, cfPass, NULL);

    CFRelease(cfUser);
    CFRelease(cfPass);
    CFRelease(rec);
    CFRelease(node);
    CFRelease(session);

    if (status == 1) {
        return 0;  // success
    } else {
        return 1;  // failure
    }
}