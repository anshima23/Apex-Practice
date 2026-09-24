public with sharing class RoomHealthService {

    public class RefreshInput {
        @InvocableVariable(required=true label='Room ID')
        public Id roomId;
    }

    public class RefreshOutput {
        @InvocableVariable public Boolean isSuccess;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Refresh Room Health Snapshot' description='Recomputes snapshot fields for given Room IDs')
    public static List<RefreshOutput> refreshHealthSnapshotFromFlow(List<RefreshInput> inputs) {
        List<RefreshOutput> outputs = new List<RefreshOutput>();

        if (inputs == null || inputs.isEmpty()) {
            RefreshOutput emptyResult = new RefreshOutput();
            emptyResult.isSuccess = false;
            emptyResult.message = 'No Room record provided for refresh.';
            outputs.add(emptyResult);
            return outputs;
        }

        Set<Id> roomIds = new Set<Id>();
        for (RefreshInput input : inputs) {
            if (input.roomId != null) {roomIds.add(input.roomId);}
        }

        try {
            recalculateRoomHealth(roomIds);
            
            for (RefreshInput input : inputs) {
                RefreshOutput res = new RefreshOutput();
                res.isSuccess = true;
                res.message = 'Health snapshot refreshed successfully.';
                outputs.add(res);
            }
        } catch (Exception e) {
            Error_Log__c log = new Error_Log__c(
                Source__c = 'RoomHealthService.refreshHealthSnapshotFromFlow',
                Message__c = e.getMessage() + '\nStack Trace:\n' + e.getStackTraceString()
            );
            insert log;

            for (RefreshInput input : inputs) {
                RefreshOutput res = new RefreshOutput();
                res.isSuccess = false;
                res.message = 'An unexpected error occurred while refreshing the health snapshot.';
                outputs.add(res);
            }
        }

        return outputs;
    }

    public static void recalculateRoomHealth(Set<Id> roomIds) {
        if (roomIds == null || roomIds.isEmpty()) { return;}

        List<Booking__c> bookings = [ SELECT Id, Room__c, Status__c, Actual_Check_Out__c, Stay_Charge__c  FROM Booking__c  WHERE Room__c IN :roomIds  AND Status__c IN ('Checked Out', 'Disputed') ];
        Map<Id, Date> maxCheckOutMap = new Map<Id, Date>();
        Map<Id, Decimal> maxStayChargeMap = new Map<Id, Decimal>();
        Map<Id, Integer> openDisputesMap = new Map<Id, Integer>();

        for (Booking__c b : bookings) {
            if (b.Status__c == 'Checked Out') {
                if (b.Actual_Check_Out__c != null) {
                    Date curDate = maxCheckOutMap.get(b.Room__c);
                    if (curDate == null || b.Actual_Check_Out__c > curDate) { maxCheckOutMap.put(b.Room__c, b.Actual_Check_Out__c);}
                }
                if (b.Stay_Charge__c != null) {
                    Decimal curCharge = maxStayChargeMap.get(b.Room__c);
                    if (curCharge == null || b.Stay_Charge__c > curCharge) { maxStayChargeMap.put(b.Room__c, b.Stay_Charge__c);}
                }
            } else if (b.Status__c == 'Disputed') {
                Integer count = openDisputesMap.containsKey(b.Room__c) ? openDisputesMap.get(b.Room__c) : 0;
                openDisputesMap.put(b.Room__c, count + 1);
            }
        }

        List<Room__c> roomsToUpdate = new List<Room__c>();

        for (Id roomId : roomIds) {
            Date maxDate = maxCheckOutMap.get(roomId);
            Decimal maxCharge = maxStayChargeMap.get(roomId);
            Integer disputes = openDisputesMap.containsKey(roomId) ? openDisputesMap.get(roomId) : 0;

            String healthTier = 'Standard';
            if (disputes >= 1) {healthTier = 'Attention';}    
            else if (maxCharge != null && maxCharge >= 15000) {healthTier = 'Premium';}

            roomsToUpdate.add(new Room__c(
                Id = roomId,
                Last_Check_Out_Date__c = maxDate,
                Highest_Stay_Charge__c = maxCharge,
                Open_Disputes__c = disputes,
                Health_Tier__c = healthTier
            ));
        }

        if (!roomsToUpdate.isEmpty()) { update roomsToUpdate;}
    }
}