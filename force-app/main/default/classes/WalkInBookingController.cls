public with sharing class WalkInBookingController {

    public class BookingRequest {
        @InvocableVariable(required=true) public Id guestId;
        @InvocableVariable(required=true) public String roomType;
        @InvocableVariable(required=true) public String floor;
        @InvocableVariable(required=true) public Date checkInDate;
        @InvocableVariable(required=true) public Date checkOutDate;
    }

    public class BookingResult {
        @InvocableVariable public Boolean isAvailable = false;
        @InvocableVariable public Boolean isSuccess = true;
        @InvocableVariable public String roomName;
        @InvocableVariable public Decimal nightlyRate;
        @InvocableVariable public Decimal totalCharge;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Process Walk-in Booking' description='Selects room, computes charge, and creates booking.')
    public static List<BookingResult> processBooking(List<BookingRequest> requests) {
        List<BookingResult> results = new List<BookingResult>();

        for (BookingRequest req : requests) {
            BookingResult res = new BookingResult();
            try {
                // Find cheapest 'Ready' room (tie-breaker: Name ASC)
                List<Room__c> rooms = [SELECT Id, Name, Nightly_Rate__c FROM Room__c WHERE Room_Type__c = :req.roomType   AND Floor__c = :req.floor AND Status__c = 'Ready' ORDER BY Nightly_Rate__c ASC, Name ASC  LIMIT 1];

                if (rooms.isEmpty()) {
                    res.isAvailable = false;
                    res.message = 'Nothing is available for that Room Type and Floor.';
                    results.add(res);
                    continue;
                }

                Room__c selectedRoom = rooms[0];
                
                // Chargeable nights = (Check-Out - Check-In) + 1
                Integer nights = req.checkInDate.daysBetween(req.checkOutDate) + 1;
                Decimal calculatedTotalCharge = nights * selectedRoom.Nightly_Rate__c;

                // Create booking record using Stay_Charge__c
                Booking__c newBooking = new Booking__c(
                    Guest__c = req.guestId,
                    Room__c = selectedRoom.Id,
                    Check_In_Date__c = req.checkInDate,
                    Check_Out_Due__c = req.checkOutDate,
                    Status__c = 'Reserved',
                    Stay_Charge__c = calculatedTotalCharge
                );
                insert newBooking;

                res.isAvailable = true;
                res.roomName = selectedRoom.Name;
                res.nightlyRate = selectedRoom.Nightly_Rate__c;
                res.totalCharge = calculatedTotalCharge;

            } catch (Exception e) {
              Error_Log__c log = new Error_Log__c(
              Error_Message__c = e.getMessage(),
              Stack_Trace__c   = e.getStackTraceString(),
              Source__c        = 'WalkInBookingController'
            );
            insert log;

            // User-friendly error message return/throw karna
            throw new AuraHandledException('Something went wrong during booking. Please contact support.');
            }

                res.isSuccess = false;
                res.message = 'An unexpected error occurred while processing the booking. Please contact support.';
            }
            results.add(res);
        }
        return results;
    }
}