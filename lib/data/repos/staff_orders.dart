// Barrel for staff orders slice (ARCH-02 split).
// Keeps `import 'staff_orders_repository.dart'` working while implementation
// lives in focused files: staff_orders_db / staff_orders_models /
// staff_orders_pure / staff_orders_repository.
//
// New code should import the specific file directly or via this barrel;
// this barrel is for backward compat.
export 'staff_orders_db.dart';
export 'staff_orders_models.dart';
export 'staff_orders_pure.dart';
export 'staff_orders_repository.dart'
    hide
        StaffPermissionException,
        rethrowAsTyped,
        StaffOrdersDb,
        SupabaseStaffOrdersDb,
        StaffOrder,
        CheckInInput,
        VisitRecorded,
        DriverOption,
        stampMinSpendDefaultEgp,
        fallbackAvgPrepMinutes,
        staffBoardPageLimit,
        OrderItemLine,
        parseItemLines,
        itemsSummaryLine,
        transitionOrderPatch,
        orderEventInsertRow,
        checkInVisitRow,
        checkInStaffLogRow,
        elapsedMinutesSince,
        averagePrepMinutes,
        formatPickupSlotCairo,
        formatExpectedReadyCairo;
