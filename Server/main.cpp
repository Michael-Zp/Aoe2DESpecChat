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
#include <optional>
#include <array>

#define DEBUG_OUTPUT 1

static const int BUF_SIZE = 1024;

typedef std::array<char, 128> MyKey;

static_assert(BUF_SIZE >= sizeof(MyKey) + 3, "Key + protocol overhead can not be bigger than a BUF_SIZE");

struct ClientThread
{
    std::thread Thread;
    bool* Done;
};

std::optional<MyKey> getKey(char *buf)
{
   if(strncmp(buf, "Key", 3) == 0)
   {
	MyKey ret;
	memcpy(&ret, buf + 3, sizeof(MyKey));
	return ret;
   }
   return {};
}

bool isKillMessage(char *buf)
{
   return strncmp(buf, "KillMe", 6) == 0;
}

void managePlayerConnection(std::shared_ptr<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int playerConnection, bool* done)
{
    char buf[BUF_SIZE];
    int readBytes;

    bool hasKey = false;
    MyKey key;

    while(!*done)
    {
        readBytes = read(playerConnection, buf, BUF_SIZE - 1);

	if(DEBUG_OUTPUT)
	    std::cout << "Read player message" << std::endl;

	buf[readBytes] = '\0';

	auto possibleKey = getKey(buf);

	if(possibleKey.has_value())
	{
	    if(DEBUG_OUTPUT)
		std::cout << "Read player key" << std::endl;

	    key = possibleKey.value();
	    hasKey = true;

	    if(DEBUG_OUTPUT)
		std::cout << "Player with key: " << std::string(std::begin(key), std::end(key)) << " connected." << std::endl;

	}

	if(hasKey)
	{
	    auto outputPair = &(*headerToOutput)[key];
	    auto mtx = &outputPair->first;
	    auto outputVector = &outputPair->second;


	    if(isKillMessage(buf))
	    {
	        int n = sprintf(buf, "%s\0", "KillMe");
	        mtx->lock();
	        outputVector->push_back(std::string(buf));
	        mtx->unlock();
	        *done = true;
	        break;
	    }

	    mtx->lock();
	    outputVector->push_back(std::string(buf));
	    mtx->unlock();

	}
    }

    close(playerConnection);
}

void casterSendLoop(std::shared_ptr<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int casterConnection, MyKey& key, bool& run)
{
    while(run)
    {
        MyKey currentKey;
        memcpy(&currentKey, &key, sizeof(MyKey));

        auto outputPair = &(*headerToOutput)[currentKey];
        auto mtx = &outputPair->first;
        auto outputVector = &outputPair->second;

        mtx->lock();
        if(outputVector->size() > 0)
        {
            for(int i = 0; i < outputVector->size(); ++i)
            {
	        send(casterConnection, (*outputVector)[i].c_str(), (*outputVector)[i].size(), 0);
            }
            outputVector->clear();
        }
        mtx->unlock();
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
}

void manageCasterConnection(std::shared_ptr<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int casterConnection, bool* done)
{
    char buf[BUF_SIZE];
    int readBytes;

    MyKey key;
    bool run = true;
    bool hasKey = false;
    std::thread sendThread;

    while(!hasKey)
    {
        readBytes = read(casterConnection, buf, BUF_SIZE - 1);

	buf[readBytes] = '\0';

	auto possibleKey = getKey(buf);

	if(possibleKey.has_value())
	{
	    key = possibleKey.value();
	    hasKey = true;

	    if(DEBUG_OUTPUT)
		std::cout << "Caster with key: " << std::string(std::begin(key), std::end(key)) << " connected." << std::endl;

	}

	if(hasKey)
        {
	    sendThread = std::thread(casterSendLoop, headerToOutput, casterConnection, std::ref(key), std::ref(run));
        }
    }

    while(!*done)
    {
	readBytes = read(casterConnection, buf, BUF_SIZE - 1);

	buf[readBytes] = '\0';

	auto possibleKey = getKey(buf);

	if(possibleKey.has_value())
	{
	    memcpy(&key, buf, sizeof(MyKey));
	    if(DEBUG_OUTPUT)
		std::cout << "Caster with key: " << std::string(std::begin(key), std::end(key)) << " connected." << std::endl;
	}
    }

    run = false;
    sendThread.join();

    close(casterConnection);
}



void waitForPlayers(std::shared_ptr<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int playerSocket)
{
    std::vector<ClientThread> playerThreads;
    while(true)
    {
        int playerConnection = accept(playerSocket, (struct sockaddr*)NULL, NULL);
	if(DEBUG_OUTPUT)
            std::cout << "Player connected." << std::endl;

        bool *done = new bool;
	*done = false;
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

void waitForCasters(std::shared_ptr<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int casterSocket)
{
    std::vector<ClientThread> casterThreads;
    while(true)
    {
        int casterConnection = accept(casterSocket, (struct sockaddr*)NULL, NULL);
	if(DEBUG_OUTPUT)
            std::cout << "Caster connected." << std::endl;

        bool *done = new bool;
	*done = false;
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

    auto headerToOutput = std::make_shared<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>>();

    std::thread waitForPlayersThread(waitForPlayers, headerToOutput, playerSocket);
    std::thread waitForCastersThread(waitForCasters, headerToOutput, casterSocket);

    waitForPlayersThread.join();
    waitForCastersThread.join();

    return 0;
}
