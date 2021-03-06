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


#define DEBUG_MESSAGES 1
#define DEBUG_CONNECTIONS 1

static const uint64_t BUF_SIZE = 1024;

struct GeneralHeader
{
    uint16_t Size;
    uint8_t Type;

    static constexpr uint8_t TypeKey = 11;
    static constexpr uint8_t TypeMessage = 22;
    static constexpr uint8_t TypeTimestamp = 33;
} __attribute__((packed));

struct MessageHeader
{
    GeneralHeader General;
    uint8_t PlayerNumber;
    uint32_t Timestamp;
} __attribute__((packed));

struct TimestampHeader
{
    GeneralHeader General;
    uint32_t Timestamp;
} __attribute__((packed));

struct OutputMessageHeader
{
    uint16_t Size;
    uint32_t PlayerID;
    uint8_t PlayerNumber;
} __attribute__((packed));

struct TimedMessage
{
    uint32_t Timestamp;
    std::shared_ptr<uint8_t[]> Bytes;
};

struct OutputMessages
{
    std::mutex Mtx;
    std::vector<TimedMessage> Messages;
};

struct ClientThread
{
    std::thread Thread;
    bool* Done;
    bool Joined;
};

typedef std::array<uint8_t, 128> MyKey;

static_assert(BUF_SIZE >= sizeof(MyKey) + sizeof(GeneralHeader), "Key + protocol overhead can not be bigger than a BUF_SIZE");

struct CasterData
{
    MyKey CurrentKey;
    bool Run;
    uint32_t Timestamp;
    uint32_t SendMessages;
};

std::optional<MyKey> getKey(const uint8_t *buf, GeneralHeader *header)
{
    if(header->Type == GeneralHeader::TypeKey)
    {
    	MyKey ret;
	    memset(&ret, 0, sizeof(MyKey));
	    memcpy(&ret, buf + sizeof(GeneralHeader), header->Size - sizeof(GeneralHeader));
	    return ret;
    }
    return {};
}

uint64_t keyHashForDebugging(const MyKey& key)
{
    uint64_t sum = 0;
    for(int i = 0; i < sizeof(MyKey); i++)
    {
	    sum += key[i];
    }
    return sum;
}

std::atomic<uint32_t> nextID;

uint32_t getNextID()
{
    return nextID++;
}

enum LogType
{
    Messages,
    Connections,
    Errors
};

void log(std::string message, LogType type)
{
    bool shouldWriteLog =
        type == LogType::Messages && DEBUG_MESSAGES ||
        type == LogType::Connections && DEBUG_CONNECTIONS ||
        type == LogType::Errors;

    if(!shouldWriteLog)
    {
        return;
    }

    const int bufferSize = 80;
    time_t rawtime;
    struct tm* timeinfo;
    char buffer[bufferSize];

    time(&rawtime);
    timeinfo = localtime(&rawtime);
    strftime(buffer, bufferSize, "./logs/%F.log", timeinfo);

    FILE* logFile = fopen(buffer, "a");

    fputs(message.c_str(), logFile);
    fputs("\n", logFile);

    fclose(logFile);
}

void managePlayerConnection(std::shared_ptr<std::map<MyKey, OutputMessages>> headerToOutput, int playerConnection, bool* done)
{
    uint8_t buf[BUF_SIZE];
    ssize_t readBytes;

    bool hasKey = false;
    MyKey key;
    uint32_t id = getNextID();

    log("Player connection with ID" + std::to_string(id) + " created.", LogType::Connections);
    //if(DEBUG_CONNECTIONS)
    //    std::cout << "Player connection with ID " << id << " created." << std::endl;

    int notFinishedMessageSize = 0;
    while((readBytes = read(playerConnection, buf + notFinishedMessageSize, BUF_SIZE - 1 - notFinishedMessageSize)) > 0)
    {
    	buf[readBytes] = '\0';

        log("Read player message with length: " + std::to_string(readBytes), LogType::Messages);
	    //if(DEBUG_MESSAGES)
	    //    std::cout << "Read player message: '" << buf << "' with length: " << readBytes << std::endl;

        if(readBytes < sizeof(GeneralHeader))
        {
            notFinishedMessageSize = readBytes;
            continue;
        }

	    int startOfNextMessage = 0;

    	while(startOfNextMessage + sizeof(GeneralHeader) < readBytes)
	    {
            uint8_t *currentBuf = buf + startOfNextMessage;

            GeneralHeader *genHeader = reinterpret_cast<GeneralHeader*>(currentBuf);

            if(startOfNextMessage + genHeader->Size > readBytes)
            {
                break;
            }

            auto possibleKey = getKey(currentBuf, genHeader);

	        if(possibleKey)
	        {
                log("Read player key", LogType::Messages);
		        //if(DEBUG_MESSAGES)
		        //    std::cout << "Read player key" << std::endl;

		        key = possibleKey.value();
		        hasKey = true;

                log("Player with key: " + std::to_string(keyHashForDebugging(key)) + " connected.", LogType::Connections);
		        //if(DEBUG_MESSAGES || DEBUG_CONNECTIONS)
		        //    std::cout << "Player with key: " << keyHashForDebugging(key) << " connected." << std::endl;
	        }
	        else if(hasKey)
	        {
		        OutputMessages& outputMessages = (*headerToOutput)[key];

                if(startOfNextMessage + genHeader->Size > readBytes)
                {
                    break;
                }

                uint32_t outMessageSize = genHeader->Size - sizeof(MessageHeader) + sizeof(OutputMessageHeader);
                MessageHeader *mesHeader = reinterpret_cast<MessageHeader*>(currentBuf);
                TimedMessage message = {mesHeader->Timestamp, std::shared_ptr<uint8_t[]>(new uint8_t[outMessageSize])};
                OutputMessageHeader *outHeader = reinterpret_cast<OutputMessageHeader*>(message.Bytes.get());
                outHeader->Size = outMessageSize;
                outHeader->PlayerID = id;
                outHeader->PlayerNumber = mesHeader->PlayerNumber;
                memcpy(message.Bytes.get() + sizeof(OutputMessageHeader), currentBuf + sizeof(MessageHeader), genHeader->Size - sizeof(MessageHeader));

                log("Adding message with lenght " + std::to_string(outHeader->Size) + " to " + std::to_string(outputMessages.Messages.size()) + " in the outputMessages of this connection.", LogType::Messages);
                //if(DEBUG_MESSAGES)
                //    std::cout << "Adding message with lenght " << outHeader->Size << " to " << outputMessages.Messages.size() << " in the outputMessages of this connection." << std::endl;

		        outputMessages.Mtx.lock();
		        outputMessages.Messages.push_back(message);
		        outputMessages.Mtx.unlock();
	        }

            startOfNextMessage += genHeader->Size;
    	}

	    notFinishedMessageSize = readBytes - startOfNextMessage;
	    memcpy(buf, buf + startOfNextMessage, notFinishedMessageSize);

        log("Start waiting for next player message at: " + std::to_string(notFinishedMessageSize), LogType::Messages);
	    //if(DEBUG_MESSAGES)
	    //    std::cout << "Start waiting for next player message at: " << notFinishedMessageSize << std::endl;
    }


    log("Closing player connection with key: " + std::to_string(keyHashForDebugging(key)), LogType::Connections);
    //if(DEBUG_CONNECTIONS)
	//    std::cout << "Closing player connection with key: " << keyHashForDebugging(key) << std::endl;

    close(playerConnection);

    *done = true;
}

void casterSendLoop(std::shared_ptr<std::map<MyKey, OutputMessages>> headerToOutput, int casterConnection, CasterData& casterData)
{
    while(casterData.Run)
    {
        MyKey currentKey;
        memcpy(&currentKey, &casterData.CurrentKey, sizeof(MyKey));

        OutputMessages& outputMessages = (*headerToOutput)[currentKey];

        outputMessages.Mtx.lock();

        for(int i = casterData.SendMessages; i < outputMessages.Messages.size(); ++i)
        {
            if(outputMessages.Messages[i].Timestamp < casterData.Timestamp)
            {
                OutputMessageHeader *outHeader = reinterpret_cast<OutputMessageHeader*>(outputMessages.Messages[i].Bytes.get());

                log("Send to caster. Key: " + std::to_string(keyHashForDebugging(casterData.CurrentKey)) + " MessageLen: " + std::to_string(outHeader->Size), LogType::Messages);
     	    	//if(DEBUG_MESSAGES)
                //    std::cout << "Send to caster. Key: " << keyHashForDebugging(casterData.CurrentKey) << " MessageLen: " << outHeader->Size << std::endl;

                send(casterConnection, outputMessages.Messages[i].Bytes.get(), outHeader->Size, 0);

                ++casterData.SendMessages;
            }
            else
            {
                break;
            }
        }

        outputMessages.Mtx.unlock();
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
}


void manageCasterConnection(std::shared_ptr<std::map<MyKey, OutputMessages>> headerToOutput, int casterConnection, bool* done)
{
    uint8_t buf[BUF_SIZE];
    ssize_t readBytes;

    bool sendThreadStarted = false;
    bool hasKey = false;
    std::thread sendThread;

    CasterData casterData;
    casterData.Run = true;
    casterData.SendMessages = 0;

    int notFinishedMessageSize = 0;
    while((readBytes = read(casterConnection, buf + notFinishedMessageSize, BUF_SIZE - 1 - notFinishedMessageSize)) > 0)
    {
    	buf[readBytes] = '\0';

        log("Read caster message with length: " + std::to_string(readBytes), LogType::Messages);
	    //if(DEBUG_MESSAGES)
	    //    std::cout << "Read caster message: '" << buf << "' with length: " << readBytes << std::endl;

        if(readBytes < sizeof(GeneralHeader))
        {
            notFinishedMessageSize = readBytes;
            continue;
        }

	    int startOfNextMessage = 0;

    	while(startOfNextMessage + sizeof(GeneralHeader) < readBytes)
	    {
            uint8_t *currentBuf = buf + startOfNextMessage;

            GeneralHeader *genHeader = reinterpret_cast<GeneralHeader*>(currentBuf);

            if(startOfNextMessage + genHeader->Size > readBytes)
            {
                break;
            }

            auto possibleKey = getKey(currentBuf, genHeader);

	        if(possibleKey)
	        {
                if(hasKey)
                {
        	        memcpy(&casterData.CurrentKey, possibleKey.value().data(), sizeof(MyKey));
                    casterData.SendMessages = 0;

                    log("Updated caster key to: " + std::to_string(keyHashForDebugging(casterData.CurrentKey)), LogType::Connections);
	                //if(DEBUG_MESSAGES || DEBUG_CONNECTIONS)
	                //    std::cout << "Updated caster key to: " << keyHashForDebugging(casterData.CurrentKey) << std::endl;
                }
                else
                {
		            casterData.CurrentKey = possibleKey.value();
		            hasKey = true;
        	        sendThreadStarted = true;
       	            sendThread = std::thread(casterSendLoop, headerToOutput, casterConnection, std::ref(casterData));

                    log("Caster with key: " + std::to_string(keyHashForDebugging(casterData.CurrentKey)) + " connected.", LogType::Connections);
	                //if(DEBUG_MESSAGES || DEBUG_CONNECTIONS)
    		        //    std::cout << "Caster with key: " << keyHashForDebugging(casterData.CurrentKey) << " connected." << std::endl;
                }
	        }
            else if(hasKey)
            {
                TimestampHeader *timeHeader = reinterpret_cast<TimestampHeader*>(currentBuf);
                casterData.Timestamp = timeHeader->Timestamp;

                log("Caster with key " + std::to_string(keyHashForDebugging(casterData.CurrentKey)) + " updated timestamp to " + std::to_string(casterData.Timestamp), LogType::Messages);
            }

            startOfNextMessage += genHeader->Size;
    	}

	    notFinishedMessageSize = readBytes - startOfNextMessage;
	    memcpy(buf, buf + startOfNextMessage, notFinishedMessageSize);

        log("Start waiting for next caster message at: " + std::to_string(notFinishedMessageSize), LogType::Messages);
	    //if(DEBUG_MESSAGES)
	    //    std::cout << "Start waiting for next caster message at: " << notFinishedMessageSize << std::endl;
    }

    if(sendThreadStarted)
    {
    	casterData.Run = false;
	    sendThread.join();
    }

    log("Closing caster connection with key: " + std::to_string(keyHashForDebugging(casterData.CurrentKey)), LogType::Connections);
    //if(DEBUG_CONNECTIONS)
    //	std::cout << "Closing caster connection with key: " << keyHashForDebugging(casterData.CurrentKey) << std::endl;

    close(casterConnection);

    *done = true;
}



void waitForPlayers(std::shared_ptr<std::map<MyKey, OutputMessages>> headerToOutput, int playerSocket)
{
    std::vector<ClientThread> playerThreads;
    while(true)
    {
        int playerConnection = accept(playerSocket, (struct sockaddr*)NULL, NULL);

        log("Player connected.", LogType::Connections);
    	//if(DEBUG_CONNECTIONS)
        //    std::cout << "Player connected." << std::endl;

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

void waitForCasters(std::shared_ptr<std::map<MyKey, OutputMessages>> headerToOutput, int casterSocket)
{
    std::vector<ClientThread> casterThreads;
    while(true)
    {
        int casterConnection = accept(casterSocket, (struct sockaddr*)NULL, NULL);

        log("Caster connected.", LogType::Connections);
    	//if(DEBUG_CONNECTIONS)
        //    std::cout << "Caster connected." << std::endl;

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
        log("Error creating caster socket! Error code" + std::string(strerror(errno)), LogType::Errors);
        //std::cout << "Error creating caster socket! Error code: " << strerror(errno) << std::endl;
        return -1;
    }

    int on = 1;
    if(setsockopt(casterSocket, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on)) < 0)
    {
        log("Error setting socket option for caster! Error code: " + std::string(strerror(errno)), LogType::Errors);
        //std::cout << "Error setting socket option for caster! Error code: " << strerror(errno) << std::endl;
        return -1;
    }

    int playerSocket = 0, playerConnection = 0;
    playerSocket = socket(AF_INET, SOCK_STREAM, 0);

    if(setsockopt(playerSocket, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on)) < 0)
    {
        log("Error setting socket option for player! Error code: " + std::string(strerror(errno)), LogType::Errors);
        //std::cout << "Error setting socket option for player! Error code: " << strerror(errno) << std::endl;
        return -1;
    }


    struct sockaddr_in ipOfServer;
    memset(&ipOfServer, '0', sizeof(ipOfServer));
    ipOfServer.sin_family = AF_INET;
    ipOfServer.sin_addr.s_addr = htonl(INADDR_ANY);

    ipOfServer.sin_port = htons(CASTER_PORT);
    if((bind(casterSocket, (struct sockaddr*)&ipOfServer , sizeof(ipOfServer))) < 0)
    {
        log("Error binding caster socket! Error code: " + std::string(strerror(errno)), LogType::Errors);
        //std::cout << "Error binding caster socket! Error code: " << strerror(errno) << std::endl;
        return -1;
    }

    if((listen(casterSocket, 20)) < 0)
    {
        log("Error start listening caster socket! Error code: " + std::string(strerror(errno)), LogType::Errors);
        //std::cout << "Error start listening caster socket! Error code: " << std::string(strerror(errno)) << std::endl;
        return -1;
    }

    ipOfServer.sin_port = htons(PLAYER_PORT);
    bind(playerSocket, (struct sockaddr*)&ipOfServer , sizeof(ipOfServer));
    listen(playerSocket, 20);

    auto headerToOutput = std::make_shared<std::map<MyKey, OutputMessages>>();

    std::thread waitForPlayersThread(waitForPlayers, headerToOutput, playerSocket);
    std::thread waitForCastersThread(waitForCasters, headerToOutput, casterSocket);

    waitForPlayersThread.join();
    waitForCastersThread.join();

    return 0;
}
