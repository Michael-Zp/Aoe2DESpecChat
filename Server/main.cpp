#define CASTER_PORT 40320
#define HOSTER_PORT 40321

#include <stdio.h> // standard input and output library
#include <stdlib.h> // this includes functions regarding memory allocation
#include <string.h> // contains string functions
#include <errno.h> //It defines macros for reporting and retrieving error conditions through error codes
#include <unistd.h> //contains various constants
#include <sys/types.h> //contains a number of basic derived types that should be used whenever appropriate
#include <arpa/inet.h> // defines in_addr structure
#include <sys/socket.h> // for socket creation
#include <netinet/in.h> //contains constants and structures needed for internet domain addresses
#include <thread>
#include <iostream>
#include <vector>

void threadingFunction(int casterConnection, int hosterConnection, bool* done)
{
    const int SIZE = 1024;
    char buf[SIZE];
    int readBytes;

    while(!*done)
    {
        readBytes = read(hosterConnection, buf, SIZE - 1);

        buf[readBytes] = '\0';
        if(strncmp(buf, "KillMe", 6) == 0)
        {
            int n = sprintf(buf, "%s\0", "KillMe");
            send(casterConnection, buf, n, 0);
            *done = true;
            break;
        }
        send(casterConnection, buf, readBytes, 0);
    }

    close(hosterConnection);
    close(casterConnection);
}

struct ClientThread
{
    std::thread Thread;
    bool* Done;
};

int main()
{
    int casterSocket = 0, casterConnection = 0;
    if((casterSocket = socket(AF_INET, SOCK_STREAM, 0)) < 0)
    {
        std::cout << "Error createing caster socket! Error code: " << strerror(errno) << std::endl;
        return -1;
    }

    int on = 1;
    if(setsockopt(casterSocket, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on)) < 0)
    {
       std::cout << "Error setting socket option for caster! Error code: " << strerror(errno) << std::endl;
       return -1;
    }

    int hosterSocket = 0, hosterConnection = 0;
    hosterSocket = socket(AF_INET, SOCK_STREAM, 0);

    if(setsockopt(hosterSocket, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on)) < 0)
    {
       std::cout << "Error setting socket option for hoster! Error code: " << strerror(errno) << std::endl;
       return -1;
    }


    struct sockaddr_in ipOfServer;
    memset(&ipOfServer, '0', sizeof(ipOfServer));
    ipOfServer.sin_family = AF_INET;
    ipOfServer.sin_addr.s_addr = htonl(INADDR_ANY);

    ipOfServer.sin_port = htons(CASTER_PORT);
    if((bind(casterSocket, (struct sockaddr*)&ipOfServer , sizeof(ipOfServer))) < 0)
    {
        std::cout << "Error binding caster socket! Error code: " << strerror(errno) << std::endl;
        return -1;
    }

    if((listen(casterSocket, 20)) < 0)
    {
        std::cout << "Error start listening caster socket! Error code: " << strerror(errno) << std::endl;
        return -1;
    }

    ipOfServer.sin_port = htons(HOSTER_PORT);
    bind(hosterSocket, (struct sockaddr*)&ipOfServer , sizeof(ipOfServer));
    listen(hosterSocket, 20);


    std::vector<ClientThread> clientThreads;

    while(true)
    {
        int casterConnection = accept(casterSocket, (struct sockaddr*)NULL, NULL);
        std::cout << "Caster connected." << std::endl;

        int hosterConnection = accept(hosterSocket, (struct sockaddr*)NULL, NULL);
        std::cout << "Hoster connected." << std::endl;

        bool *done = new bool;
        std::thread thread(threadingFunction, casterConnection, hosterConnection, done);
        clientThreads.push_back({std::move(thread), done});

        for(auto& ct : clientThreads)
        {
            if(*ct.Done)
            {
                ct.Thread.join();
            }
        }
    }



    return 0;
}