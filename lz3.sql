--1.
CREATE DATABASE SalesDB
USE SalesDB

CREATE TABLE Customers (
	CustomerID INT IDENTITY(1, 1) PRIMARY KEY,
	FullName NVARCHAR(100) NOT NULL,
	Email NVARCHAR(100) UNIQUE NOT NULL,
	RegistrationDate DATETIME NOT NULL DEFAULT GETDATE()
)

CREATE TABLE Orders (
	OrderID INT IDENTITY(1, 1) PRIMARY KEY,
	CustomerID INT NOT NULL,
	OrderTotal FLOAT NOT NULL CHECK (OrderTotal > 0),
	OrderDate DATETIME NOT NULL DEFAULT GETDATE(),
	[Status] NVARCHAR(20) NOT NULL DEFAULT 'Новый',

	FOREIGN KEY (CustomerID) REFERENCES Customers (CustomerID)
)

CREATE DATABASE LogisticsDB
USE LogisticsDB

CREATE TABLE Warehouses (
	WarehouseID INT IDENTITY(1, 1) PRIMARY KEY,
	[Location] NVARCHAR(100) UNIQUE NOT NULL,
	Capacity FLOAT NOT NULL,
	ManagerContact NVARCHAR(50) NOT NULL DEFAULT 'Не назначен',
	CreatedDate DATETIME NOT NULL DEFAULT GETDATE(),
)

CREATE TABLE Shipments (
	ShipmentID INT IDENTITY(1, 1) PRIMARY KEY,
	WarehouseID INT,
	OrderID INT,
	TrackingCode NVARCHAR(50) UNIQUE NOT NULL,
	[Weight] FLOAT NOT NULL,
	DispathDate DATETIME NULL DEFAULT GETDATE(),
	[Status] NVARCHAR(20) NOT NULL DEFAULT 'Ожидает отправки',

	FOREIGN KEY (WarehouseID) REFERENCES Warehouses (WarehouseID)
)

GO
CREATE TRIGGER CheckOrderID
ON Shipments
AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM inserted
        LEFT JOIN [SalesDB].[dbo].[Orders] ON inserted.OrderID = [SalesDB].[dbo].[Orders].OrderID
        WHERE [SalesDB].[dbo].[Orders].OrderID IS NULL
    )
    BEGIN
        ROLLBACK TRANSACTION;
		RAISERROR ('Ошибка: нет такого OrderID', 1, 1);
    END
END
GO


--2. Select
USE SalesDB

GO
CREATE FUNCTION fn_GetCustomers()
	RETURNS TABLE
	AS
	RETURN (SELECT * FROM Customers)
GO

GO
CREATE FUNCTION fn_GetOrders()
	RETURNS TABLE
	AS
	RETURN (SELECT * FROM Orders)
GO

GO
CREATE FUNCTION fn_GetOrdersByStatus(@status NVARCHAR(20))
	RETURNS TABLE
	AS
	RETURN (SELECT * FROM Orders WHERE Orders.[Status] = @status)
GO


USE LogisticsDB
GO
CREATE FUNCTION fn_GetShipmentsByWarehouse(@wid INT)
	RETURNS TABLE
	AS
	RETURN (SELECT * FROM Shipments WHERE Shipments.WarehouseID = @wid)
GO

GO
CREATE FUNCTION fn_GetShipments()
	RETURNS TABLE
	AS
	RETURN (SELECT * FROM Shipments)
GO

GO
CREATE FUNCTION fn_GetWarehouses()
	RETURNS TABLE
	AS
	RETURN (SELECT * FROM Warehouses)
GO


--3. Кросс-базовый триггер
USE SalesDB

GO
CREATE TRIGGER SalesDB_Orders
    ON Orders
    AFTER INSERT, UPDATE
AS
BEGIN
	IF UPDATE([Status])
		BEGIN
			INSERT INTO LogisticsDB.dbo.Shipments  (WarehouseID, OrderID, TrackingCode, [Weight], DispathDate, [Status])
				SELECT 1, inserted.OrderID, CAST(CURRENT_TIMESTAMP AS NVARCHAR(20)), 1.0, NULL, 'Ожидает отправки' FROM inserted
					JOIN deleted ON inserted.OrderID = deleted.OrderID
					WHERE inserted.[Status] = 'Подтвержден'
		END
END
GO


--4. Тестовые сценарии
USE SalesDB
INSERT INTO Customers (FullName, Email) VALUES ('Анатолий Карпов', 'karpov@email.com')
INSERT INTO Customers (FullName, Email) VALUES ('Андрюха Гомель', 'andre@email.com')
INSERT INTO Orders (CustomerID, OrderTotal) VALUES (1, 5.5)

SELECT * FROM dbo.fn_GetCustomers()
SELECT * FROM dbo.fn_GetOrders()

USE LogisticsDB
INSERT INTO Warehouses ([Location], Capacity) VALUES ('г. Минск', 500.0)
SELECT * FROM dbo.fn_GetWarehouses()

USE SalesDB
UPDATE Orders SET [Status] = 'Подтвержден'

USE LogisticsDB
SELECT * FROM dbo.fn_GetShipments()

USE SalesDB
INSERT INTO Orders (CustomerID, OrderTotal) VALUES (1, 0)
SELECT * FROM dbo.fn_GetOrders()

GO
CREATE PROCEDURE CustomerProblemUpdate
	AS
BEGIN
	BEGIN TRANSACTION
		BEGIN TRY
			UPDATE Customers SET Email = (SELECT TOP (1) Email From Customers)
			COMMIT TRANSACTION
		END TRY
		BEGIN CATCH
			ROLLBACK TRANSACTION
			RAISERROR('Ошибка транзакции', 0, 0)
		END CATCH
END

EXEC CustomerProblemUpdate
SELECT * FROM dbo.fn_GetCustomers()
