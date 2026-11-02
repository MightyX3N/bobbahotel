package com.bobbahotel;

import com.eu.habbo.Emulator;
import com.eu.habbo.messages.rcon.RCONMessage;
import com.google.gson.Gson;

/** RCON "bobbanavigator": reloads the navigator's public rooms (after the admin pages change them). */
public class UpdateNavigatorRcon extends RCONMessage<UpdateNavigatorRcon.Data> {
    public UpdateNavigatorRcon() {
        super(Data.class);
    }

    @Override
    public void handle(Gson gson, Data json) {
        Emulator.getGameEnvironment().getNavigatorManager().loadNavigator();
        this.message = "ok";
    }

    public static class Data {
    }
}
