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
#include <sstream>
#include <atomic>
#include <algorithm>


#define DEBUG_MESSAGES 0
#define DEBUG_CONNECTIONS 0

static const int BUF_SIZE = 1024;

typedef std::array<char, 128> MyKey;

static_assert(BUF_SIZE >= sizeof(MyKey) + 3, "Key + protocol overhead can not be bigger than a BUF_SIZE");

struct ClientThread
{
    std::thread Thread;
    bool* Done;
    bool Joined;
};

std::optional<MyKey> getKey(const char *buf, int len)
{
    if(strncmp(buf, "Key", 3) == 0)
    {
	MyKey ret;
	memset(&ret, 0, sizeof(MyKey));
	memcpy(&ret, buf + 3, len - 3);
	ret[len - 3] = '\0';
	return ret;
    }
    return {};
}

int keyHashForDebugging(const MyKey& key)
{
    uint64_t sum = 0;
    for(int i = 0; i < sizeof(MyKey); i++)
    {
	sum += key[i];
    }
    return sum;
}

std::atomic<uint64_t> nextID;

uint64_t getNextID()
{
    return nextID++;
}

struct MessageMetaData
{
    int MessageLength;
    int MessageOffset;
};

std::optional<MessageMetaData> getMessageMetaData(char* buf, int maxLength)
{
    MessageMetaData ret;
    for(int i = 0; i < maxLength; ++i)
    {
	if(buf[i] == ';')
	{
	    if(DEBUG_MESSAGES)
	        std::cout << "Found message size at: " << i << std::endl;

	    std::string lenString(buf, i);

	    if(DEBUG_MESSAGES)
	        std::cout << "Found message with length: " << lenString << " , where length string is " << lenString.size() << " characters long." << std::endl;

	    ret.MessageLength = std::stoi(lenString);
	    ret.MessageOffset = lenString.size() + 1;

	    if(ret.MessageLength + ret.MessageOffset > maxLength)
	    {
		return {};
	    }

	    return ret;
	}
    }
    return {};
}

void managePlayerConnection(std::shared_ptr<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int playerConnection, bool* done)
{
    char buf[BUF_SIZE];
    int readBytes;

    bool hasKey = false;
    MyKey key;
    uint64_t id = getNextID();

    if(DEBUG_CONNECTIONS)
        std::cout << "Player connection with ID " << id << " created." << std::endl;

    int notFinishedMessageSize = 0;
    while((readBytes = read(playerConnection, buf + notFinishedMessageSize, BUF_SIZE - 1 - notFinishedMessageSize)) > 0)
    {
	buf[readBytes] = '\0';

	if(DEBUG_MESSAGES)
	    std::cout << "Read player message: '" << buf << "' with length: " << readBytes << std::endl;

	auto messageMetaData = getMessageMetaData(buf, readBytes);
	int startOfNextMessage = 0;

	while(messageMetaData.has_value() && (startOfNextMessage + messageMetaData.value().MessageLength) < readBytes)
	{
	    int startOfThisMessage = startOfNextMessage + messageMetaData.value().MessageOffset;
	    std::string messageString(buf + startOfThisMessage, messageMetaData.value().MessageLength);
	    startOfNextMessage = startOfThisMessage + messageMetaData.value().MessageLength;

	    if(DEBUG_MESSAGES)
	        std::cout << "Len = " << messageMetaData.value().MessageLength << ". Start processing message: " << messageString << std::endl;

	    auto possibleKey = getKey(messageString.c_str(), messageMetaData.value().MessageLength);

	    if(possibleKey.has_value())
	    {
		if(DEBUG_MESSAGES)
		    std::cout << "Read player key" << std::endl;

		key = possibleKey.value();
		hasKey = true;

		if(DEBUG_MESSAGES || DEBUG_CONNECTIONS)
		    std::cout << "Player with key: " << keyHashForDebugging(key) << " connected." << std::endl;
	    }
	    else if(hasKey)
	    {
		auto outputPair = &(*headerToOutput)[key];
		auto mtx = &outputPair->first;
		auto outputVector = &outputPair->second;

		std::stringstream outSs;

		outSs << id << ";" << messageString << '\n';

		if(DEBUG_MESSAGES)
		    std::cout << "Adding player message: " << outSs.str() << std::endl;

		mtx->lock();
		outputVector->push_back(outSs.str());
		mtx->unlock();
	    }

	    messageMetaData = getMessageMetaData(buf + startOfNextMessage, readBytes - startOfNextMessage);
	}

	notFinishedMessageSize = readBytes - startOfNextMessage;
	memcpy(buf, buf + startOfNextMessage, notFinishedMessageSize);
    }


    if(DEBUG_CONNECTIONS)
	std::cout << "Closing player connection with key: " << keyHashForDebugging(key) << std::endl;

    close(playerConnection);

    *done = true;
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
		if(DEBUG_MESSAGES)
		    std::cout << "Send to caster. Key: " << keyHashForDebugging(key) << " Message: " << (*outputVector)[i] << std::endl;

	        send(casterConnection, (*outputVector)[i].c_str(), (*outputVector)[i].size(), 0);
            }
            outputVector->clear();
        }
        mtx->unlock();
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
}

void manageCasterConnection(std::shared_ptr<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int casterConnection, bool* done)
{
    char buf[BUF_SIZE];
    int readBytes;

    MyKey key;
    bool run = true;
    bool sendThreadStarted = false;
    bool hasKey = false;
    std::thread sendThread;

    int messageStart = 0;
    while(!hasKey)
    {
        readBytes = read(casterConnection, buf + messageStart, BUF_SIZE - messageStart - 1);

	if(readBytes <= 0)
	{
	    break;
	}

	buf[readBytes] = '\0';

	auto messageMetaData = getMessageMetaData(buf, readBytes);

	if(messageMetaData.has_value())
	{
            auto possibleKey = getKey(buf + messageMetaData.value().MessageOffset, messageMetaData.value().MessageLength);

	    if(possibleKey.has_value())
	    {
	        key = possibleKey.value();
	        hasKey = true;

	        if(DEBUG_MESSAGES || DEBUG_CONNECTIONS)
		    std::cout << "Caster with key: " << keyHashForDebugging(key) << " connected." << std::endl;
	    }

	    if(hasKey)
            {
	        sendThreadStarted = true;
	        sendThread = std::thread(casterSendLoop, headerToOutput, casterConnection, std::ref(key), std::ref(run));
            }
	}
	else
	{
	    messageStart = readBytes;
	}
    }

    messageStart = 0;
    while((readBytes = read(casterConnection, buf + messageStart, BUF_SIZE - messageStart - 1)) > 0)
    {
	buf[readBytes] = '\0';

	auto messageMetaData = getMessageMetaData(buf, readBytes);

	if(messageMetaData.has_value())
	{
            auto possibleKey = getKey(buf + messageMetaData.value().MessageOffset, messageMetaData.value().MessageLength);

	    if(possibleKey.has_value())
	    {
	        memcpy(&key, possibleKey.value().data(), sizeof(MyKey));

	        if(DEBUG_MESSAGES || DEBUG_CONNECTIONS)
	            std::cout << "Updated caster key to: " << keyHashForDebugging(key) << std::endl;
	    }
	}
	else
	{
	    messageStart = readBytes;
	}
    }

    if(sendThreadStarted)
    {
	run = false;
	sendThread.join();
    }

    if(DEBUG_CONNECTIONS)
	std::cout << "Closing caster connection with key: " << keyHashForDebugging(key) << std::endl;

    close(casterConnection);

    *done = true;
}



void waitForPlayers(std::shared_ptr<std::map<MyKey, std::pair<std::mutex, std::vector<std::string>>>> headerToOutput, int playerSocket)
{
    std::vector<ClientThread> playerThreads;
    while(true)
    {
        int playerConnection = accept(playerSocket, (struct sockaddr*)NULL, NULL);
	if(DEBUG_CONNECTIONS)
            std::cout << "Player connected." << std::endl;

        bool *done = new bool;
	*done = false;
        std::thread thread(managePlayerConnection, headerToOutput, playerConnection, done);
        playerThreads.push_back({std::move(thread), done, false});

        for(auto& pt : playerThreads)
        {
            if(*pt.Done)
            {
                pt.Thread.join();
		pt.Joined = true;
            }
        }

	for(int i = 0; i < playerThreads.size(); ++i)
	{
	    if(*(playerThreads[i].Done) && playerThreads[i].Joined)
	    {
		playerThreads.erase(playerThreads.begin() + i);
		--i;
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
	if(DEBUG_CONNECTIONS)
            std::cout << "Caster connected." << std::endl;

        bool *done = new bool;
	*done = false;
        std::thread thread(manageCasterConnection, headerToOutput, casterConnection, done);
        casterThreads.push_back({std::move(thread), done, false});

        for(auto& ct : casterThreads)
        {
            if(*ct.Done)
            {
		ct.Thread.join();
		ct.Joined = true;
            }
        }

	for(int i = 0; i < casterThreads.size(); ++i)
	{
	    if(*(casterThreads[i].Done) && casterThreads[i].Joined)
	    {
		casterThreads.erase(casterThreads.begin() + i);
		--i;
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
