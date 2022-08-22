import NonFungibleToken from "./interfaces/NonFungibleToken.cdc"
import FungibleToken from "./interfaces/FungibleToken.cdc"
import FlowToken from "./tokens/FlowToken.cdc"

pub contract Domains: NonFungibleToken {

    // Declare global variables to track domains owners and domain expiration times
    pub let owners: {String: Address}
    pub let expirationTimes: {String: UFix64}

    // Helper functions
    pub fun isAvailable(nameHash: String): Bool {
        if self.owners[nameHash] == nil {
            return  true
        }
        return self.isExpired(nameHash: nameHash)
    }

    // Returns the expiry time of a domain
    pub fun getExpirationTime(nameHash: String): UFix64? {
        return self.expirationTimes[nameHash]

    }

    // Checks if a domain is expired
    pub fun isExpired(nameHash: String): Bool {
        let currTime = getCurrentBlock().timestamp
        let expTime = self.expirationTimes[nameHash]
        if expTime != nil {
            return currTime >= expTime!
        }
        return false
    }

    // Returns the entire `owners` dictionary
    pub fun getAllOwners(): {String: Address} {
        return self.owners
    }
    
    // Returns the entire `expirationTimes` dictionary
    pub fun getAllExpirationTimes(): {String: UFix64}  {
        return self.expirationTimes
    }

    // Update the owner of a domain
    access(account) fun updateOwner(nameHash: String, address: Address?) {
        self.owners[nameHash] = address
    }

    // Update the expiration time of a domain
    access(account) fun updateExpirationTime(nameHash: String, expTime: UFix64) {
        self.expirationTimes[nameHash] = expTime
    }

    // Events
    pub event DomainBioChanged(nameHash: String, bio: String)
    pub event DomainAddressChanged(nameHash: String, address: Address)
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)


    // Struct representing the information pertaining to an FNS domain
    pub struct DomainInfo {
        pub let id: UInt64
        pub let owner: Address
        pub let name: String
        pub let nameHash: String
        pub let expiresAt: UFix64?
        pub let address: Address?
        pub let bio: String
        pub let createdAt: UFix64

        //Struct Initializer
        init(
            id: UInt64,
            owner: Address,
            name: String,
            nameHash: String,
            expiresAt: UFix64?,
            address: Address?,
            bio: String,
            createdAt: UFix64
        ) {
            self.id = id
            self.owner = owner
            self.name = name
            self.nameHash = nameHash
            self.expiresAt = expiresAt
            self.address = address
            self.bio = bio
            self.createdAt = createdAt

        }
        
    }

    pub resource interface DomainPublic {
        pub let id: UInt64
        pub let name: String
        pub let nameHash: String
        pub let createdAt: UFix64

        pub fun getBio(): String
        pub fun getAddress(): Address?
        pub fun getDomainName(): String
        pub fun getInfo(): DomainInfo
        
    }

    pub resource interface DomainPrivate {
        pub fun setBio(bio: String)
        pub fun setAddress(addr: Address)
    }

    pub resource NFT: DomainPublic , DomainPrivate, NonFungibleToken.INFT{
        pub let id: UInt64
        pub let name: String
        pub let nameHash: String
        pub let createdAt: UFix64

        // access(self) implies that only the code within this resource
        // can read/modify this variable directly
        // This is similar to `private` in Solidity
        access(self) var address: Address?
        access(self) var bio: String

        init(id: UInt64, name: String, nameHash: String) {
            self.id = id
            self.name = name
            self.nameHash = nameHash
            self.createdAt = getCurrentBlock().timestamp
            self.address = nil
            self.bio = ""
        }

        pub fun getBio(): String {
            return self.bio
        }

        pub fun getAddress(): Address? {
            return self.address
        }
        
        pub fun getDomainName(): String {
            return self.name.concat(".fns")
        }

        pub fun setBio(bio: String) {
            pre {
                Domains.isExpired(nameHash: self.nameHash) == false: "Domain is expired"
            }
            self.bio = bio
            emit DomainBioChanged(nameHash: self.nameHash, bio: bio)
        }

        pub fun setAddress(addr: Address){
            pre {
                Domains.isExpired(nameHash: self.nameHash) == false: "Domain is expired"
            }
            self.address = addr
            emit DomainAddressChanged(nameHash: self.nameHash, address: addr)
        }

        pub fun getInfo(): DomainInfo {
            let owner = Domains.owners[self.nameHash]!
            return DomainInfo(
                id: self.id,
                owner: owner,
                name: self.getDomainName(),
                nameHash: self.nameHash,
                expiresAt: Domains.expirationTimes[self.nameHash],
                address: self.address,
                bio: self.bio,
                createdAt: self.createdAt
            )
        }
    }

    pub resource interface CollectionPublic {
        pub fun borrowDomain(id: UInt64): &{Domains.DomainPublic}
        
    }

    pub resource interface CollectionPrivate {
        access(account) fun mintDomain(name: String, nameHash: String, expiresAt: UFix64, receiver: Capability<&{NonFungibleToken.Receiver}>)
        pub fun borrowDomainPrivate(id: UInt64): &Domains.NFT
    }

    pub resource Collection: CollectionPublic, CollectionPrivate, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
        // Dictionary (mapping) of Token ID -> NFT Resource
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        init() {
            // Initializes as an empty resource
            self.ownedNFTs <- {}
        }

        // NonFungibleToken.Provider
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let domain <- self.ownedNFTs.remove(key: withdrawID)
                ?? panic("NFT not found in collection")
            emit Withdraw(id: domain.id, from: self.owner?.address)
            return <-domain
        }

        // NonFungibleToken.Receiver
        pub fun deposit(token: @NonFungibleToken.NFT) {
            // Typecast the generic NFT resource as a Domains.NFT resource
            let domain <- token as! @Domains.NFT
            let id = domain.id
            let nameHash = domain.nameHash

            if Domains.isExpired(nameHash: nameHash) {
                panic("Domain is expired")
            }

            Domains.updateOwner(nameHash: nameHash, address: self.owner?.address)

            let oldToken <- self.ownedNFTs[id] <- domain
            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }

        // NonFungibleToken.CollectionPublic
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }
        
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return (&self.ownedNFTs[id] as &NonFungibleToken.NFT?)!
        }

        
    }




}