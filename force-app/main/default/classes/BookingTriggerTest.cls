@IsTest
private class BookingTriggerTest {

    private static String getValidPicklistValue(Schema.SObjectField field) {
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static SObjectType getGuestSObjectType() {
        return Booking__c.Guest__c.getDescribe().getReferenceTo()[0];
    }

    @TestSetup
    static void setupData() {
        SObjectType guestType = getGuestSObjectType();
        SObject guestObj = guestType.newSObject();
        
        Map<String, Schema.SObjectField> fields = guestType.getDescribe().fields.getMap();
        if (fields.containsKey('LastName')) {
            guestObj.put('LastName', 'Test Guest');
        } else if (fields.containsKey('Name')) {
            guestObj.put('Name', 'Test Guest');
        }
        insert guestObj;

        String validFloor = getValidPicklistValue(Room__c.Floor__c);
        String validRoomType = getValidPicklistValue(Room__c.Room_Type__c);

        List<Room__c> rooms = new List<Room__c>{
            new Room__c(
                Name = 'Room 101', 
                Status__c = 'Ready',
                Floor__c = validFloor,
                Nightly_Rate__c = 150.00,
                Room_Type__c = validRoomType
            ),
            new Room__c(
                Name = 'Room 102', 
                Status__c = 'Ready',
                Floor__c = validFloor,
                Nightly_Rate__c = 200.00,
                Room_Type__c = validRoomType
            )
        };
        insert rooms;
    }

    private static Id getTestGuestId() {
        String objectName = getGuestSObjectType().getDescribe().getName();
        return Database.query('SELECT Id FROM ' + objectName + ' LIMIT 1')[0].Id;
    }

    @IsTest
    static void testValidCheckInAndHealthRecalculation() {
        Room__c room = [SELECT Id, Status__c FROM Room__c WHERE Name = 'Room 101' LIMIT 1];
        Id guestId = getTestGuestId();

        Test.startTest();
        Booking__c booking = new Booking__c(
            Room__c = room.Id,
            Guest__c = guestId,
            Status__c = 'Checked In',
            Check_In_Date__c = Date.newInstance(2026, 8, 11),
            Check_Out_Due__c = Date.newInstance(2026, 8, 16)
        );
        insert booking;
        Test.stopTest();

        Room__c updatedRoom = [SELECT Id, Status__c FROM Room__c WHERE Id = :room.Id];
        System.assertEquals('Occupied', updatedRoom.Status__c, 'Room status should be Occupied after check-in.');
    }

    @IsTest
    static void testInvalidCheckInWhenRoomNotReady() {
        Room__c room = [SELECT Id, Status__c FROM Room__c WHERE Name = 'Room 101' LIMIT 1];
        Id guestId = getTestGuestId();

        room.Status__c = 'Occupied';
        update room;

        Booking__c booking = new Booking__c(
            Room__c = room.Id,
            Guest__c = guestId,
            Status__c = 'Checked In',
            Check_In_Date__c = Date.newInstance(2026, 8, 11),
            Check_Out_Due__c = Date.newInstance(2026, 8, 16)
        );

        Test.startTest();
        try {
            insert booking;
            System.assert(false, 'Expected DML Exception due to room not being Ready');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('This room is not ready for check-in.'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testHealthTierPriorityAttention() {
        Room__c room = [SELECT Id FROM Room__c WHERE Name = 'Room 101' LIMIT 1];
        Id guestId = getTestGuestId();

        Booking__c disputedBooking = new Booking__c(
            Room__c = room.Id,
            Guest__c = guestId,
            Status__c = 'Disputed',
            Stay_Charge__c = 20000,
            Check_In_Date__c = Date.newInstance(2026, 8, 11),
            Check_Out_Due__c = Date.newInstance(2026, 8, 16)
        );
        
        Test.startTest();
        insert disputedBooking;
        Test.stopTest();

        Room__c updatedRoom = [SELECT Id, Health_Tier__c, Open_Disputes__c FROM Room__c WHERE Id = :room.Id];
        System.assertEquals('Attention', updatedRoom.Health_Tier__c);
        System.assertEquals(1, updatedRoom.Open_Disputes__c);
    }

    @IsTest
    static void testHealthTierPriorityPremium() {
        Room__c room = [SELECT Id FROM Room__c WHERE Name = 'Room 101' LIMIT 1];
        Id guestId = getTestGuestId();

        Booking__c premiumBooking = new Booking__c(
            Room__c = room.Id,
            Guest__c = guestId,
            Status__c = 'Checked Out',
            Actual_Check_Out__c = Date.today(),
            Stay_Charge__c = 16000,
            Check_In_Date__c = Date.newInstance(2026, 8, 11),
            Check_Out_Due__c = Date.newInstance(2026, 8, 16)
        );

        Test.startTest();
        insert premiumBooking;
        Test.stopTest();

        Room__c updatedRoom = [SELECT Id, Health_Tier__c, Highest_Stay_Charge__c FROM Room__c WHERE Id = :room.Id];
        System.assertEquals('Premium', updatedRoom.Health_Tier__c);
        System.assertEquals(16000, updatedRoom.Highest_Stay_Charge__c);
    }

    @IsTest
    static void testPreventDeleteActiveBooking() {
        Room__c room = [SELECT Id FROM Room__c WHERE Name = 'Room 101' LIMIT 1];
        Id guestId = getTestGuestId();

        Booking__c booking = new Booking__c(
            Room__c = room.Id,
            Guest__c = guestId,
            Status__c = 'Checked In',
            Check_In_Date__c = Date.newInstance(2026, 8, 11),
            Check_Out_Due__c = Date.newInstance(2026, 8, 16)
        );
        insert booking;

        Test.startTest();
        try {
            delete booking;
            System.assert(false, 'Expected error when deleting active booking');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Bookings with activity on record cannot be removed.'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testInvocableRoomHealthService() {
        Room__c room = [SELECT Id FROM Room__c WHERE Name = 'Room 101' LIMIT 1];

        RoomHealthService.RefreshInput input = new RoomHealthService.RefreshInput();
        input.roomId = room.Id;

        Test.startTest();
        List<RoomHealthService.RefreshOutput> outputs = RoomHealthService.refreshHealthSnapshotFromFlow(
            new List<RoomHealthService.RefreshInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].isSuccess);
    }
}