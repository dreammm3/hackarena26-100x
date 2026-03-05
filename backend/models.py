from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from database import Base
import datetime

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    plaid_items = relationship("PlaidItem", back_populates="owner")
    ghost_addresses = relationship("GhostAddress", back_populates="owner")
    usage_stats = relationship("UsageData", back_populates="owner")

class PlaidItem(Base):
    __tablename__ = "plaid_items"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    access_token = Column(String, unique=True, index=True)
    item_id = Column(String, unique=True, index=True)
    owner = relationship("User", back_populates="plaid_items")
    transactions = relationship("Transaction", back_populates="item")

class Transaction(Base):
    __tablename__ = "transactions"
    id = Column(Integer, primary_key=True, index=True)
    item_id = Column(Integer, ForeignKey("plaid_items.id"))
    transaction_id = Column(String, unique=True, index=True)
    amount = Column(Float)
    merchant_name = Column(String, index=True)
    description = Column(String)
    date = Column(DateTime)
    category = Column(String)
    item = relationship("PlaidItem", back_populates="transactions")

class GhostAddress(Base):
    __tablename__ = "ghost_addresses"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    email_address = Column(String, unique=True, index=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    is_active = Column(Integer, default=1)
    owner = relationship("User", back_populates="ghost_addresses")
    inbound_emails = relationship("InboundEmail", back_populates="ghost")

class InboundEmail(Base):
    __tablename__ = "inbound_emails"
    id = Column(Integer, primary_key=True, index=True)
    ghost_id = Column(Integer, ForeignKey("ghost_addresses.id"))
    sender = Column(String)
    subject = Column(String)
    body = Column(String)
    received_at = Column(DateTime, default=datetime.datetime.utcnow)
    ghost = relationship("GhostAddress", back_populates="inbound_emails")

class UsageData(Base):
    __tablename__ = "usage_data"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    package_name = Column(String, index=True)
    app_name = Column(String)
    minutes_used = Column(Integer)
    last_time_used = Column(DateTime)
    date = Column(DateTime, default=datetime.datetime.utcnow)
    
    owner = relationship("User", back_populates="usage_stats")
