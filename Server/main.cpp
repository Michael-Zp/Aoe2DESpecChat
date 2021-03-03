#define CASTER_PORT 40320
#define PLAYER_PORT 40321

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
#include <map>
#include <chrono>
#include <mutex>

#define DEBUG_OUTPUT 1

struct ClientThread
{
    std::thread Thread;
    bool* Done;
};


void managePlayerConnection(std::shared_ptr<std::map<std::string, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int playerConnection, bool* done)
{
    static const int SIZE = 1024;
    static const int HEADER_SIZE = 128;
    static_assert(SIZE >= HEADER_SIZE, "Buffer size is smaller than header size");
    char buf[SIZE];
    int readBytes;

    readBytes = read(playerConnection, buf, HEADER_SIZE - 1);
    buf[HEADER_SIZE] = '\0';

    auto key = std::string(buf);

    if(DEBUG_OUTPUT)
	std::cout << "Player with key: " << key << " connected." << std::endl;

    auto& outputPair = (*headerToOutput)[key];
    auto& mtx = outputPair.first;
    auto& outputVector = outputPair.second;

    while(!*done)
    {
        readBytes = read(playerConnection, buf, SIZE - 1);

        buf[readBytes] = '\0';
        if(strncmp(buf, "KillMe", 6) == 0)
        {
            int n = sprintf(buf, "%s\0", "KillMe");
	    mtx.lock();
	    outputVector.push_back(std::string(buf));
	    mtx.unlock();
            *done = true;
            break;
        }

	mtx.lock();
	outputVector.push_back(std::string(buf));
	mtx.unlock();
    }

    close(playerConnection);
}

void manageCasterConnection(std::shared_ptr<std::map<std::string, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int casterConnection, bool* done)
{
    static const int SIZE = 1024;
    static const int HEADER_SIZE = 128;
    static_assert(SIZE >= HEADER_SIZE, "Buffer size is smaller than header size");
    char buf[SIZE];
    int readBytes;

    readBytes = read(casterConnection, buf, HEADER_SIZE - 1);
    buf[HEADER_SIZE] = '\0';

    auto key = std::string(buf);

    if(DEBUG_OUTPUT)
	std::cout << "Caster with key: " << key << " connected." << std::endl;

    auto& outputPair = (*headerToOutput)[key];
    auto& mtx = outputPair.first;
    auto& outputVector = outputPair.second;

    while(!*done)
    {
	mtx.lock();
	if(outputVector.size() > 0)
	{
	    for(int i = 0; i < outputVector.size(); ++i)
	    {
		if(outputVector[i] == "KillMe")
		{
		    send(casterConnection, outputVector[i].c_str(), outputVector[i].size(), 0);
		    *done = true;
		    break;
		}
		send(casterConnection, outputVector[i].c_str(), outputVector[i].size(), 0);
	    }
	    outputVector.clear();
	}
	mtx.unlock();
	std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    close(casterConnection);
}



void waitForPlayers(std::shared_ptr<std::map<std::string, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int playerSocket)
{
    std::vector<ClientThread> playerThreads;
    while(true)
    {
        int playerConnection = accept(playerSocket, (struct sockaddr*)NULL, NULL);
	if(DEBUG_OUTPUT)
            std::cout << "Player connected." << std::endl;

        bool *done = new bool;
        std::thread thread(managePlayerConnection, headerToOutput, playerConnection, done);
        playerThreads.push_back({std::move(thread), done});

        for(auto& pt : playerThreads)
        {
            if(*pt.Done)
            {
                pt.Thread.join();
            }
        }
    }
}

void waitForCasters(std::shared_ptr<std::map<std::string, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int casterSocket)
{
    std::vector<ClientThread> casterThreads;
    while(true)
    {
        int casterConnection = accept(casterSocket, (struct sockaddr*)NULL, NULL);
	if(DEBUG_OUTPUT)
            std::cout << "Caster connected." << std::endl;

        bool *done = new bool;
        std::thread thread(manageCasterConnection, headerToOutput, casterConnection, done);
        casterThreads.push_back({std::move(thread), done});

        for(auto& ct : casterThreads)
        {
            if(*ct.Done)
            {
                ct.Thread.join();
            }
        }
    }
}


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

    int playerSocket = 0, playerConnection = 0;
    playerSocket = socket(AF_INET, SOCK_STREAM, 0);

    if(setsockopt(playerSocket, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on)) < 0)
    {
       std::cout << "Error setting socket option for player! Error code: " << strerror(errno) << std::endl;
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

    ipOfServer.sin_port = htons(PLAYER_PORT);
    bind(playerSocket, (struct sockaddr*)&ipOfServer , sizeof(ipOfServer));
    listen(playerSocket, 20);

    auto headerToOutput = std::make_shared<std::map<std::string, std::pair<std::mutex, std::vector<std::string>>>>();

    std::thread waitForPlayersThread(waitForPlayers, headerToOutput, playerSocket);
    std::thread waitForCastersThread(waitForCasters, headerToOutput, casterSocket);

    waitForPlayersThread.join();
    waitForCastersThread.join();

    return 0;
}
