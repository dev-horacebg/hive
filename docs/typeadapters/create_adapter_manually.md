# Create adapter manually

Sometimes it might be necessary to create a custom `TypeAdapter`. You can do that by extending the `TypeAdapter` class. Make sure to specify the generic argument.

{% hint style="warning" %}
Test your custom `TypeAdapter`s thoroughly. If one does not work correctly, it may corrupt your box.
{% endhint %}

It is very easy to implement a `TypeAdapter`. Keep in mind that `TypeAdapter`s have to be immutable! Here is the `DataTimeAdapter` used by Hive internally:

```dart
class DataTimeAdapter extends TypeAdapter<DateTime> {
  @override
  DateTime read(BinaryReader reader) {
    var millis = reader.readInt();
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  void write(BinaryWriter writer, DateTime obj) {
    writer.writeInt(obj.millisecondsSinceEpoch);
  }
}
```

The `read()` method is called when your object has to be read from the disk. Use the `BinaryReader` to read all properties of your object. In the above sample it is only an `int` containing `millisecondsSinceEpoch`.  
 The `write()` method is the same just for writing the object to the disk.

{% hint style="warning" %}
Make sure, you read properties in the same order you have written them before.
{% endhint %}

