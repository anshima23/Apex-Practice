public with sharing class BookingTriggerHandler {

    public static void handleBeforeInsert(List<Booking__c> newBookings) {
        validateCheckIn(newBookings, null);
        DisputeEscalationService.stampDisputeOpenedOn(newBookings, null);
    }
  
    public static void handleBeforeUpdate(List<Booking__c> newBookings, Map<Id, Booking__c> oldMap) {
        validateCheckIn(newBookings, oldMap);
        DisputeEscalationService.stampDisputeOpenedOn(newBookings, oldMap);
    }

    public static void handleBeforeDelete(List<Booking__c> oldBookings) {
        for (Booking__c b : oldBookings) {
            if (b.Status__c != 'Reserved' && b.Status__c != 'Cancelled') {
                b.addError('Bookings with activity on record cannot be removed.');
            }
        }
    }

    public static void handleAfterInsert(List<Booking__c> newBookings) {
        processAfterSave(newBookings, null);
        DisputeEscalationService.processDisputedBookings(newBookings, null);
        RefundSettlementService.processRefunds(newBookings, null);
    }

    public static void handleAfterUpdate(List<Booking__c> newBookings, Map<Id, Booking__c> oldMap) {
        processAfterSave(newBookings, oldMap);
        DisputeEscalationService.processDisputedBookings(newBookings, oldMap);
        RefundSettlementService.processRefunds(newBookings, oldMap);
    }

    public static void handleAfterDelete(Map<Id, Booking__c> oldMap) {
        processAfterSave(null, oldMap);
    }

    public static void handleAfterUndelete(List<Booking__c> newBookings) {
        processAfterSave(newBookings, null);
    }

    private static void validateCheckIn(List<Booking__c> newBookings, Map<Id, Booking__c> oldMap) {
        Set<Id> roomIdsToCheck = new Set<Id>();
        List<Booking__c> checkInCandidates = new List<Booking__c>();

        for (Booking__c b : newBookings) {
            Boolean isCheckingIn = (b.Status__c == 'Checked In');
            Boolean wasCheckingIn = (oldMap != null && oldMap.containsKey(b.Id) && oldMap.get(b.Id).Status__c == 'Checked In');

            if (isCheckingIn && (!wasCheckingIn || (oldMap != null && b.Room__c != oldMap.get(b.Id).Room__c))) {
                if (b.Room__c != null) {
                    roomIdsToCheck.add(b.Room__c);
                    checkInCandidates.add(b);
                }
            }
        }

        if (checkInCandidates.isEmpty()) return;

        Map<Id, Room__c> roomsMap = new Map<Id, Room__c>([SELECT Id, Status__c FROM Room__c WHERE Id IN :roomIdsToCheck]);
        Set<Id> claimedRoomsInBatch = new Set<Id>();

        for (Booking__c b : checkInCandidates) {
            Room__c targetRoom = roomsMap.get(b.Room__c);

            if (targetRoom == null || targetRoom.Status__c != 'Ready' || claimedRoomsInBatch.contains(b.Room__c)) { b.addError('This room is not ready for check-in.');}
            else {claimedRoomsInBatch.add(b.Room__c);}
        }
    }

    private static void processAfterSave(List<Booking__c> newList, Map<Id, Booking__c> oldMap) {
        Set<Id> affectedRoomIds = new Set<Id>();
        Map<Id, String> roomStatusUpdates = new Map<Id, String>();

        if (newList != null) {
            for (Booking__c b : newList) {
                if (b.Room__c != null) {affectedRoomIds.add(b.Room__c);}
                Booking__c oldB = oldMap != null ? oldMap.get(b.Id) : null;
                Boolean isNew = (oldB == null);
                Boolean statusChanged = (!isNew && b.Status__c != oldB.Status__c);
                Boolean roomChanged = (!isNew && b.Room__c != oldB.Room__c);

                if (isNew || statusChanged || roomChanged) {
                    if (b.Status__c == 'Checked In' && b.Room__c != null) {roomStatusUpdates.put(b.Room__c, 'Occupied');}    
                    else if (oldB != null && oldB.Status__c == 'Checked In' &&  (b.Status__c == 'Checked Out' || b.Status__c == 'Cancelled')) {
                        if (oldB.Room__c != null) {roomStatusUpdates.put(oldB.Room__c, 'Ready');}
                    }
                }
                if (oldB != null && oldB.Room__c != null) {affectedRoomIds.add(oldB.Room__c);}
            }
        } else if (oldMap != null) {
            for (Booking__c b : oldMap.values()) {
                if (b.Room__c != null) { affectedRoomIds.add(b.Room__c);}
            }
        }

        if (!roomStatusUpdates.isEmpty()) {
            List<Room__c> statusRooms = new List<Room__c>();
            for (Id rId : roomStatusUpdates.keySet()) {
                statusRooms.add(new Room__c(Id = rId, Status__c = roomStatusUpdates.get(rId)));
            }
            update statusRooms;
        }

        if (!affectedRoomIds.isEmpty()) {
            RoomHealthService.recalculateRoomHealth(affectedRoomIds);
        }
    }
}