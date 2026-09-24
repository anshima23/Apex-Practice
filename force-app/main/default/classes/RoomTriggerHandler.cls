public with sharing class RoomTriggerHandler {
    public static void handleBefore(List<Room__c> newList) {
        Map<Id, Room__c> queriedMap = getMissingDataMap(newList);
        Map<String, RoomWrapper> keyToBestRoomMap = new Map<String, RoomWrapper>();

        for (Room__c room : newList) {
            if (room.Featured_Room__c == true) {
                RoomWrapper candidate = new RoomWrapper(room, queriedMap.get(room.Id));
                String key = candidate.key;

                if (!keyToBestRoomMap.containsKey(key)) { keyToBestRoomMap.put(key, candidate);}
                else {
                    RoomWrapper currentBest = keyToBestRoomMap.get(key);
                    if (isBetterCandidate(candidate, currentBest)) {
                        currentBest.record.Featured_Room__c = false;
                        keyToBestRoomMap.put(key, candidate);
                    } 
                    else { room.Featured_Room__c = false;}
                }
            }
        }
    }

    public static void handleAfter(List<Room__c> newList) {
        Map<Id, Room__c> queriedMap = getMissingDataMap(newList);
        Map<String, Id> winningRoomMap = new Map<String, Id>();
        List<String> floors = new List<String>();
        List<String> roomTypes = new List<String>();

        //triggered list me se un rooms ko seperate krna jinka featuredRoom checkbox tick hai aur room ka key(floor,roomType) match kr rha hai combination se
        for (Room__c room : newList) {
            if (room.Featured_Room__c == true) {
                RoomWrapper wrapper = new RoomWrapper(room, queriedMap.get(room.Id));
                winningRoomMap.put(wrapper.key, room.Id);
                if (wrapper.floor != null) floors.add(wrapper.floor);
                if (wrapper.roomType != null) roomTypes.add(wrapper.roomType);
            }
        }

        if (winningRoomMap.isEmpty()) { return;}

        //isshe ham check kr rhe hai ki database me same roomType aur floor ke ombination ke liye jo rooms hai usko uncehck krna
        List<Room__c> existingFeaturedRooms = [ SELECT Id, Floor__c, Room_Type__c, Featured_Room__c FROM Room__c WHERE Featured_Room__c = true AND Floor__c IN :floors AND Room_Type__c IN :roomTypes AND Id NOT IN :winningRoomMap.values()];

        List<Room__c> roomsToUncheck = new List<Room__c>();
        for (Room__c existingRoom : existingFeaturedRooms) {
            String key = buildKey(existingRoom.Floor__c, existingRoom.Room_Type__c);
            if (winningRoomMap.containsKey(key)) {
                existingRoom.Featured_Room__c = false;
                roomsToUncheck.add(existingRoom);
            }
        }

        if (!roomsToUncheck.isEmpty()) { update roomsToUncheck;}
    }

    //jb trigger sirf ek hi field pr hua ho to us time trigger object ki baki fields me null hoga to hmko database se uski fields fetch krni padegi
    private static Map<Id, Room__c> getMissingDataMap(List<Room__c> newList) {
        Set<Id> needQueryIds = new Set<Id>();
        for (Room__c r : newList) {
            if (r.Id != null && (r.Floor__c == null || r.Room_Type__c == null || r.Nightly_Rate__c == null || r.Name == null)) { needQueryIds.add(r.Id);}
        }

        if (needQueryIds.isEmpty()) { return new Map<Id, Room__c>();}
        return new Map<Id, Room__c>([ SELECT Id, Name, Floor__c, Room_Type__c, Nightly_Rate__c FROM Room__c WHERE Id IN :needQueryIds]);
    }

    //nighlty rate compare krne ke liye, agr rate same ho to alphabhet wala check kro vrna uncheck ya check kr do
    private static Boolean isBetterCandidate(RoomWrapper candidate, RoomWrapper currentBest) {
        if (candidate.rate < currentBest.rate) { return true;}
        else if (candidate.rate == currentBest.rate) {return candidate.name.compareTo(currentBest.name) < 0;}
        return false;
    }

    //for checking per floor and roomType
    private static String buildKey(String floor, String roomType) {
        String floorVal = floor != null ? floor : '';
        String typeVal = roomType != null ? roomType : '';
        return floorVal.toLowerCase() + '_' + typeVal.toLowerCase();
    }

    //is class se ham loog perfect dataset prepare krte hai triggered room ke liye.
    private class RoomWrapper {
        public Room__c record;
        public String floor;
        public String roomType;
        public Decimal rate;
        public String name;
        public String key;

        //room r me triggered room ki fields ka data aye ga aur queried me database me rkkhi fields ka data aye ga same room ke liye
        public RoomWrapper(Room__c r, Room__c queried) {
            this.record = r;
            this.floor = r.Floor__c != null ? r.Floor__c : (queried != null ? queried.Floor__c : null);
            this.roomType = r.Room_Type__c != null ? r.Room_Type__c : (queried != null ? queried.Room_Type__c : null);
            this.rate = r.Nightly_Rate__c != null ? r.Nightly_Rate__c : (queried != null && queried.Nightly_Rate__c != null ? queried.Nightly_Rate__c : 0);
            this.name = r.Name != null ? r.Name : (queried != null && queried.Name != null ? queried.Name : '');
            this.key = buildKey(this.floor, this.roomType);
        }
    }
}